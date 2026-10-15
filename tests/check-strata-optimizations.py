#!/usr/bin/env python3
"""Focused full-model A/B gate: compare token IDs within each execution mode.

Requires an idle GPU and a local model config in Strata batch_test format. Does
not manage services or contact an API. Artifacts must be outside the checkout.
"""
import argparse
import json
import os
from pathlib import Path
import queue
import shlex
import subprocess
import sys
import threading
import time


def overrides(items):
    result = {}
    for item in items:
        key, sep, value = item.partition('=')
        if not sep or not key.startswith('STRATA_') or key == 'STRATA_IQ_MT_MIN':
            raise ValueError('environment switches must be STRATA_NAME=VALUE; leave IQ_MT_MIN unchanged')
        result[key] = value
    return result


class Engine:
    def __init__(self, exe, cfg, env, extra, directory, timeout):
        self.timeout = timeout
        self.queue = queue.Queue()
        args = list(cfg['args']) + extra
        # One fixed profile, with these controls identical for both variants.
        controlled = {'--batch': '2', '--adapt-every': '1000000', '--conversation-cache-mib': '0'}
        for flag, value in controlled.items():
            while flag in args:
                i = args.index(flag)
                if i + 1 >= len(args):
                    raise ValueError(f'missing value for {flag}')
                del args[i:i + 2]
            args += [flag, value]
        if len(cfg.get('gpu') or []) > 1 and '--layer-split' not in args:
            args += ['--layer-split', str(cfg.get('layer_split') or 'auto')]
        child_env = {**os.environ, **env}
        child_env['LD_LIBRARY_PATH'] = ':'.join(cfg.get('lib_dirs', []) + [child_env.get('LD_LIBRARY_PATH', '')])
        self.log = (directory / 'engine.stderr.log').open('w')
        try:
            self.p = subprocess.Popen([exe, '--serve', *args], cwd=cfg.get('cwd'), env=child_env,
                                      stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.log,
                                      text=True, bufsize=1)
        except BaseException:
            self.log.close()
            raise
        def read():
            try:
                for line in self.p.stdout:
                    self.queue.put(line.rstrip('\n'))
            except BaseException as exc:
                self.queue.put(exc)
            finally:
                self.queue.put(None)
        self.reader = threading.Thread(target=read, daemon=True)
        self.reader.start()

    def line(self, deadline):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('engine operation exceeded timeout')
        try:
            line = self.queue.get(timeout=remaining)
        except queue.Empty as exc:
            raise TimeoutError('engine operation exceeded timeout') from exc
        if isinstance(line, BaseException):
            raise line
        if line is None:
            raise RuntimeError(f'engine stdout closed (exit={self.p.poll()}); see engine.stderr.log')
        if line.startswith('ERR'):
            raise RuntimeError(line)
        return line

    def ready(self):
        deadline = time.monotonic() + self.timeout
        while not self.line(deadline).startswith('READY'):
            pass

    def send(self, commands):
        self.p.stdin.write('\n'.join(commands) + '\n')
        self.p.stdin.flush()

    def close(self, failed):
        try:
            if self.p.poll() is None:
                if failed:
                    self.p.kill()
                else:
                    self.send(['QUIT'])
                try:
                    self.p.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    self.p.kill()
                    self.p.wait(timeout=30)
                    if not failed:
                        raise TimeoutError('engine did not exit after QUIT')
            if not failed and self.p.returncode != 0:
                raise RuntimeError(f'engine exited with status {self.p.returncode}')
        finally:
            if self.p.poll() is None:
                self.p.kill()
                self.p.wait(timeout=30)
            self.reader.join(timeout=5)
            self.p.stdin.close()
            self.p.stdout.close()
            self.log.close()


def done_fields(line):
    fields = line.split()
    if len(fields) < 9 or fields[5] not in ('length', 'stop'):
        raise RuntimeError(f'failed or malformed completion: {line}')
    return {'reported_tokens': int(fields[1]), 'prompt_tokens': int(fields[2]),
            'prompt_ms': float(fields[3]), 'decode_ms': float(fields[4]),
            'finish': fields[5], 'reused_tokens': int(fields[8])}


def generate(engine, name, prompts, count, batch):
    records = [{'name': f'{name}/{i}', 'tokens': [], 'requested_tokens': count,
                'input_tokens': len(ids)} for i, ids in enumerate(prompts)]
    commands = [(f'BGEN {i} {count}' if batch else f'GEN {count}')
                + ' temperature=0 ' + ','.join(map(str, ids)) for i, ids in enumerate(prompts)]
    deadline = time.monotonic() + engine.timeout
    start = time.monotonic()
    engine.send(commands)  # Queue both admissions together, before any batch windows.
    admitted, completed, admitting = set(), set(), 0
    peak_active = 0
    while len(completed) != len(prompts) or (batch and len(admitted) != len(prompts)):
        line = engine.line(deadline)
        fields = line.split()
        if line.startswith('T '):
            records[admitting]['tokens'].append(int(fields[1]))
        elif line.startswith('BT '):
            records[int(fields[1])]['tokens'].append(int(fields[2]))
        elif line.startswith('DONE '):
            records[admitting].update(done_fields(line))
            if batch:
                records[admitting]['admission_decode_ms'] = records[admitting].pop('decode_ms')
            if not batch:
                completed.add(admitting)
        elif line.startswith('BADM '):
            slot, continues = int(fields[1]), int(fields[2])
            if not batch or slot != admitting or 'finish' not in records[slot] or continues not in (0, 1):
                raise RuntimeError(f'unexpected admission: {line}')
            admitted.add(slot)
            if not continues:
                if records[slot]['finish'] != 'stop' and len(records[slot]['tokens']) < count:
                    raise RuntimeError(f'batch admission failed: {line}')
                completed.add(slot)
            peak_active = max(peak_active, len(admitted - completed))
            admitting += 1
        elif line.startswith('BDONE '):
            slot = int(fields[1])
            if fields[3] not in ('length', 'stop'):
                raise RuntimeError(f'failed batch completion: {line}')
            records[slot].update(reported_tokens=int(fields[2]), finish=fields[3],
                                 batch_elapsed_ms=float(fields[4]))
            completed.add(slot)
    if batch and peak_active != len(prompts):
        raise RuntimeError(f'expected {len(prompts)} active batch slots, observed {peak_active}')
    elapsed = (time.monotonic() - start) * 1000
    for record in records:
        n = len(record['tokens'])
        if not 0 < n <= count or record.get('reported_tokens') != n:
            raise RuntimeError(f"{record['name']}: incomplete or inconsistent token count")
        if record['finish'] == 'length' and n != count:
            raise RuntimeError(f"{record['name']}: generation truncated")
        record['mode_wall_ms'] = elapsed
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('exe', 'config', 'tools', 'output-dir'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--baseline-exe', help='baseline engine; defaults to --exe')
    parser.add_argument('--off-env', action='append', default=[], metavar='STRATA_NAME=VALUE')
    parser.add_argument('--on-env', action='append', default=[], metavar='STRATA_NAME=VALUE')
    parser.add_argument('--extra', default='', help='same additional engine arguments for both variants')
    parser.add_argument('--timeout', type=float, default=900, help='seconds per startup or generation mode')
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    output = Path(args.output_dir).resolve()
    if output.is_relative_to(Path(__file__).resolve().parents[1]):
        parser.error('--output-dir must be outside the checkout')
    output.mkdir(parents=True, exist_ok=False)
    cfg = json.loads(Path(args.config).read_text())
    if cfg.get('env'):
        raise ValueError('config must not load environment values; use the same calling environment for the fixed profile')
    off, on = overrides(args.off_env), overrides(args.on_env)
    if off.keys() != on.keys() or not off:
        raise ValueError('provide the same nonempty set of switches in --off-env and --on-env')
    sys.path.insert(0, args.tools)
    from batch_test import tokenizer
    tok = tokenizer(cfg['tokenizer'])
    def chat(text):
        return tok.encode('<|im_start|>user\n' + text + '<|im_end|>\n'
                          '<|im_start|>assistant\n<think>\n\n</think>\n\n', parse_special=True)
    filler = tok.encode(' '.join(f'Entry {i}: the committee reviewed the budget, schedule and open risks.'
                                for i in range(200)))[:1450]
    long_prompt = (tok.encode('<|im_start|>user\n', parse_special=True) + filler
                   + tok.encode('\nSummarize the recurring concerns in this agenda.<|im_end|>\n'
                                '<|im_start|>assistant\n<think>\n\n</think>\n\n', parse_special=True))
    modes = [('fresh-prefill', [long_prompt], 16, False),
             ('solo', [chat('Explain B-tree insertion step by step with a worked example.')], 64, False),
             ('two-slot', [chat('Write a Python interval merging function and explain its complexity.'),
                           chat('Compare TCP and QUIC handshakes and congestion control in detail.')], 64, True),
             ('one-slot', [chat('Explain how a database transaction provides isolation, with examples.')], 64, True)]
    result = {'switches': {'off': off, 'on': on}, 'variants': {}, 'equal': False}
    try:
        for variant, env in [('off', off), ('on', on)]:
            directory = output / variant
            directory.mkdir()
            records = result['variants'][variant] = []
            exe = (args.baseline_exe or args.exe) if variant == 'off' else args.exe
            engine = Engine(exe, cfg, env, shlex.split(args.extra), directory, args.timeout)
            failed = True
            try:
                engine.ready()
                for name, prompts, count, batch in modes:
                    records.extend(generate(engine, name, prompts, count, batch))
                    if name == 'fresh-prefill' and records[-1]['reused_tokens'] != 0:
                        raise RuntimeError('fresh prefill unexpectedly reused prompt tokens')
                    print(json.dumps({'variant': variant, 'completed_mode': name}), flush=True)
                failed = False
            finally:
                engine.close(failed)
        if len(result['variants']['off']) != len(result['variants']['on']):
            raise AssertionError('variant record counts differ')
        comparisons = []
        for before, after in zip(result['variants']['off'], result['variants']['on']):
            same = before['tokens'] == after['tokens'] and before['finish'] == after['finish']
            comparisons.append({'name': before['name'], 'equal': same})
        result['comparisons'] = comparisons
        result['equal'] = bool(comparisons) and all(item['equal'] for item in comparisons)
        if not result['equal']:
            raise AssertionError('candidate changed token IDs or finish reason; see result.json')
        print('PASS: exact baseline/candidate token IDs in all four modes', flush=True)
    except BaseException as exc:
        result['error'] = f'{type(exc).__name__}: {exc}'
        raise
    finally:
        (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
