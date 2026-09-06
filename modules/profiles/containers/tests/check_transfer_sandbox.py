#!/usr/bin/env python3
"""Test the built migration helper with real OpenSSH and temporary transfer data.

Usage: python3 check_transfer_sandbox.py /nix/store/.../bin/docker-migration-command
No SSH connections, Docker calls, host data writes or production transfers.
"""
import os
from pathlib import Path
import runpy
import struct
import subprocess
import sys
import tempfile


helper = runpy.run_path(sys.argv[1])
pack = lambda n: struct.pack('>I', n)
string = lambda value: pack(len(value)) + value

with tempfile.TemporaryDirectory(prefix="transfer-sandbox-test-") as temporary:
    work = Path(temporary)
    home, staging = work / "home", work / "staging"
    home.mkdir()
    staging.mkdir()
    outside = work / "outside"
    outside.write_text("outside fixture, must remain inaccessible")
    (home / "escape").symlink_to(outside)
    (home / "inside").write_bytes(b"transfer fixture")
    (home / "safe-link").symlink_to(home / "inside")
    helper['transfer_argv'].__globals__['TRANSFER_DIRECTORIES'] = (str(home), str(staging))
    command = helper['transfer_argv'](helper['command_argv'](['sftp-server']))
    server = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              env=helper['ENV'])

    def receive(size):
        data = server.stdout.read(size)
        assert len(data) == size, server.stderr.read().decode()
        return data

    def request(kind, payload):
        packet = bytes([kind]) + payload
        server.stdin.write(pack(len(packet)) + packet)
        server.stdin.flush()
        return receive(struct.unpack('>I', receive(4))[0])

    assert request(1, pack(3))[0] == 2  # INIT / VERSION
    sequence = 0

    def open_file(path, flags=1):
        global sequence
        sequence += 1
        result = request(3, pack(sequence) + string(os.fsencode(path)) + pack(flags) + pack(0))
        if result[0] == 102:  # HANDLE
            return result[5:]
        assert result[0] == 101, result
        return None

    try:
        for path in (home / 'inside', home / 'safe-link'):
            handle = open_file(path)
            assert handle is not None, path
            result = request(5, pack(100) + handle + struct.pack('>Q', 0) + pack(100))
            assert result[0] == 103 and result[9:] == b'transfer fixture', result
            assert request(4, pack(101) + handle)[0] == 101
        for directory in (home, staging):
            target = directory / 'uploaded'
            handle = open_file(target, 2 | 8 | 16)  # WRITE | CREAT | TRUNC
            assert handle is not None, target
            result = request(6, pack(102) + handle + struct.pack('>Q', 0) + string(b'uploaded fixture'))
            assert result[0] == 101 and result[5:9] == pack(0), result
            request(4, pack(103) + handle)
            assert target.read_bytes() == b'uploaded fixture'
        for path in (outside, home / 'escape', home / '..' / 'outside',
                     '/proc/self/mem', '/proc/self/maps', '/etc/shadow',
                     '/var/run/docker.sock', '/var/lib/docker-volume-migration/identity'):
            assert open_file(path) is None, f'escaped sandbox: {path}'
        assert open_file(outside, 2 | 16) is None
    finally:
        server.stdin.close()
        server.wait(timeout=5)
    assert server.returncode == 0, server.stderr.read().decode()
    assert outside.read_text() == 'outside fixture, must remain inaccessible'

    # Legacy SCP uses the same confinement, including paths inside its protocol.
    scp = helper['command_argv'](['scp', '-t', str(home)])
    result = subprocess.run(helper['transfer_argv'](scp), env=helper['ENV'],
                            input=b'C0600 6 legacy\nlegacy\x00', capture_output=True, timeout=5)
    assert result.returncode == 0, result.stderr
    assert (home / 'legacy').read_bytes() == b'legacy'
    scp = helper['command_argv'](['scp', '-f', str(home / 'escape')])
    result = subprocess.run(helper['transfer_argv'](scp), env=helper['ENV'],
                            input=b'\x00\x00', capture_output=True, timeout=5)
    assert result.returncode != 0 and b'outside fixture' not in result.stdout

print('Transfer sandbox checks passed: SFTP/SCP transfers, traversal, symlinks, host sockets and secrets')
