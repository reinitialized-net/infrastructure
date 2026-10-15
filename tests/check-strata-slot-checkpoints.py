#!/usr/bin/env python3
"""Full-model regression: preserve turn checkpoints through repeated slot/solo transfers.

Run only while the model's GPU is available. Uses a private engine, an explicit
config and the installed Strata tools; does not connect to the serving API.
"""
import argparse
import json
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', required=True)
    parser.add_argument('--config', required=True)
    parser.add_argument('--tools', required=True)
    parser.add_argument('--dump', required=True)
    args = parser.parse_args()
    sys.path.insert(0, args.tools)
    from batch_test import Engine, tokenizer

    cfg = json.loads(Path(args.config).read_text())
    tok = tokenizer(cfg['tokenizer'])

    def chat(text):
        return tok.encode('<|im_start|>user\n' + text + '<|im_end|>\n'
                          '<|im_start|>assistant\n<think>\n\n</think>\n\n', parse_special=True)

    body = '\n'.join(f'Entry {i}: the committee reviewed the budget, schedule and open risks.' for i in range(48))
    prompt = chat(body + '\nExplain how a B-tree works in detail.')
    boundary = max(i for i, t in enumerate(prompt) if t == prompt[0])
    followup = (prompt[:boundary]
                + tok.encode('<|im_start|>assistant\nA short answer.<|im_end|>\n', parse_special=True)
                + chat('Now explain insertion.'))
    # Fixed routing and one CPU arithmetic path isolate state transfers. The activation-reuse kernel has its own
    # parity gate under the service's mt_min=2; this test intentionally uses mt_min=1 for solo/slot equivalence.
    env = {**cfg.get('env', {}), 'STRATA_IQ_MT_MIN': '1'}
    engine = Engine(args.exe, cfg, 2, env, ['--adapt-every', '1000000', '--conversation-cache-mib', '0'])
    lines = engine.lines()
    records = []

    def generate(name, ids, count, slot=False):
        command = f'BGEN 0 {count}' if slot else f'GEN {count}'
        engine.send(command + ' ' + ','.join(map(str, ids)))
        output, done = [], None
        for line in lines:
            if line.startswith('T '):
                output.append(int(line.split()[1]))
            elif line.startswith('BT 0 '):
                output.append(int(line.split()[2]))
            elif line.startswith('DONE '):
                done = line.split()
                if not slot: break
            elif line.startswith('BADM 0 0') or line.startswith('BDONE 0 '):
                break
            elif line.startswith('ERR'):
                raise RuntimeError(line)
        if done is None or len(output) != count:
            raise RuntimeError(f'{name}: incomplete generation ({len(output)} of {count})')
        record = {'name': name, 'tokens': output, 'reused': int(done[8]), 'prompt_ms': float(done[3])}
        records.append(record)
        print(json.dumps({k: v for k, v in record.items() if k != 'tokens'}), flush=True)
        return output

    try:
        reference = generate('solo-reference', prompt, 64)
        expected = generate('followup-reference', followup, 32)
        generate('replace-live', chat('Say hello.'), 1)
        output = generate('slot-first', prompt, 16, slot=True)
        output += generate('solo-first-return', prompt + output, 16)
        output += generate('slot-second', prompt + output, 16, slot=True)
        output += generate('solo-second-return', prompt + output, 16)
        actual = generate('followup-after-transfers', followup, 32)
        result = {'boundary': boundary, 'continuation_equal': output == reference,
                  'followup_equal': actual == expected, 'records': records}
        Path(args.dump).write_text(json.dumps(result))
        if output != reference or actual != expected or records[-1]['reused'] < boundary:
            raise AssertionError('slot transfers changed output or lost the turn checkpoint')
        print(f'PASS: both returns preserve output; followup reuses at least {boundary} prompt tokens', flush=True)
    finally:
        if engine.p.poll() is None:
            engine.send('QUIT')
            try:
                engine.p.wait(timeout=180)
            except BaseException:
                engine.p.kill()
                engine.p.wait()
                raise


if __name__ == '__main__':
    main()
