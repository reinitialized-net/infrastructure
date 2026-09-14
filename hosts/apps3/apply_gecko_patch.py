"""Apply the reviewed Frigate patch only to its exact qualified source files."""

import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def parse_patch(text):
    lines = text.splitlines(keepends=True)
    files = {}
    index = 0
    current = None
    while index < len(lines):
        line = lines[index]
        if line.startswith('--- a/'):
            current = line[len('--- a/'):].strip()
            index += 1
            if lines[index] != '+++ b/' + current + '\n' or current in files:
                raise ValueError('Invalid patch file header')
            files[current] = []
            index += 1
            continue
        match = re.fullmatch(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@[^\n]*\n', line)
        if current is None or match is None:
            raise ValueError('Unexpected patch content')
        old_start, old_count, new_start, new_count = [int(value or 1) for value in match.groups()]
        index += 1
        old_used = new_used = 0
        body = []
        while old_used < old_count or new_used < new_count:
            entry = lines[index]
            prefix = entry[:1]
            if prefix not in (' ', '+', '-'):
                raise ValueError('Invalid patch hunk')
            old_used += prefix in (' ', '-')
            new_used += prefix in (' ', '+')
            body.append(entry)
            index += 1
        if old_used != old_count or new_used != new_count:
            raise ValueError('Patch hunk length mismatch')
        files[current].append((old_start if old_count == 0 else old_start - 1, body))
    return files


def apply_hunks(source, hunks):
    old = source.splitlines(keepends=True)
    result = []
    cursor = 0
    for start, body in hunks:
        if not cursor <= start <= len(old):
            raise ValueError('Overlapping patch hunks')
        result.extend(old[cursor:start])
        cursor = start
        for entry in body:
            prefix, content = entry[0], entry[1:]
            if prefix in (' ', '-'):
                if cursor >= len(old) or old[cursor] != content:
                    raise ValueError('Patch context mismatch')
                cursor += 1
            if prefix in (' ', '+'):
                result.append(content)
    result.extend(old[cursor:])
    return ''.join(result)


def apply(root, bundle, check_only=False):
    root = root.resolve()
    manifest = json.loads((bundle / 'frigate-gecko.json').read_text())
    patches = parse_patch((bundle / 'frigate-gecko.patch').read_text())
    if patches.keys() != manifest['files'].keys():
        raise ValueError('Patch manifest mismatch')
    changes = []
    for relative, expected in manifest['helpers'].items():
        path = root / relative
        if path.is_symlink() or not path.resolve().is_relative_to(root):
            raise ValueError('Unexpected helper path')
        data = path.read_bytes()
        if digest(data) != expected:
            raise ValueError('Unqualified gecko helper: ' + relative)
        ast.parse(data, filename=str(path))
    for relative, hashes in manifest['files'].items():
        path = root / relative
        if path.is_symlink() or not path.resolve().is_relative_to(root):
            raise ValueError('Unexpected source path')
        source = path.read_bytes()
        if digest(source) == hashes['after']:
            continue
        if digest(source) != hashes['before']:
            raise ValueError('Unqualified Frigate source: ' + relative)
        result = apply_hunks(source.decode(), patches[relative]).encode()
        if digest(result) != hashes['after']:
            raise ValueError('Patched source checksum mismatch: ' + relative)
        ast.parse(result, filename=str(path))
        changes.append((path, result))
    if not check_only:
        # Validate every file before changing any of them. Never start Frigate
        # after a mismatch; a subsequent attempt can safely finish an interrupted apply.
        for path, result in changes:
            with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
                temporary = Path(stream.name)
                try:
                    stream.write(result)
                    stream.flush()
                    os.chmod(temporary, path.stat().st_mode & 0o777)
                    temporary.replace(path)
                finally:
                    temporary.unlink(missing_ok=True)
    return len(changes)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path('/opt/frigate/frigate'))
    parser.add_argument('--check', action='store_true')
    arguments = parser.parse_args()
    count = apply(arguments.root, Path(__file__).resolve().parent, arguments.check)
    print(f'Gecko source patch verified: {count} files require application')
