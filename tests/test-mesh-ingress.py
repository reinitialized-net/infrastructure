#!/usr/bin/env python3
"""Exercise the evaluated mesh guard against DNAT in disposable network namespaces.

Usage: sudo unshare --net python3 tests/test-mesh-ingress.py /tmp/mesh-ingress.nft
The rules file is config.networking.nftables.tables.mesh-ingress.content for db1.
Refuses to run in PID 1's network namespace. No host firewall or routes change.
"""
import os
from pathlib import Path
import subprocess
import sys
import time


assert os.readlink('/proc/self/ns/net') != os.readlink('/proc/1/ns/net'), 'use unshare --net'


def run(*command, **kwargs):
    return subprocess.run(command, check=True, capture_output=True, text=True, **kwargs)


children = []
try:
    for _ in range(2):
        child = subprocess.Popen(['unshare', '--net', 'sleep', '60'])
        children.append(child)
        for attempt in range(100):
            if os.readlink(f'/proc/{child.pid}/ns/net') != os.readlink('/proc/self/ns/net'):
                break
            time.sleep(0.01)
        else:
            raise AssertionError('child network namespace did not start')
    client, backend = children

    def inside(process, *command, **kwargs):
        return run('nsenter', '-t', str(process.pid), '-n', '--', *command, **kwargs)

    for interface, peer, process, address, other in (
        ('physical', 'client', client, '192.0.2.1', '192.0.2.2'),
        ('br-mesh', 'container', backend, '172.20.0.1', '172.20.0.2'),
    ):
        run('ip', 'link', 'add', interface, 'type', 'veth', 'peer', 'name', peer)
        run('ip', 'link', 'set', peer, 'netns', str(process.pid))
        run('ip', 'addr', 'add', address + '/24', 'dev', interface)
        run('ip', 'link', 'set', interface, 'up')
        inside(process, 'ip', 'addr', 'add', other + '/24', 'dev', peer)
        inside(process, 'ip', 'link', 'set', peer, 'up')
        inside(process, 'ip', 'link', 'set', 'lo', 'up')
        inside(process, 'ip', 'route', 'add', 'default', 'via', address)
    run('ip', 'addr', 'add', '10.255.0.11/32', 'dev', 'lo')
    run('ip', 'link', 'set', 'lo', 'up')
    run('sysctl', '-qw', 'net.ipv4.ip_forward=1')
    # Model Docker's permissive publication. The guard must precede its DNAT.
    run('nft', '-f', '-', input='''
table ip docker_test {
  chain prerouting {
    type nat hook prerouting priority -100; policy accept;
    ip daddr 10.255.0.11 tcp dport 1025 dnat to 172.20.0.2:10000
    ip daddr 192.0.2.1 tcp dport 53 dnat to 172.20.0.2:10000
  }
  chain postrouting {
    type nat hook postrouting priority 100; policy accept;
    ip saddr 172.20.0.2 ip daddr 172.20.0.2 tcp dport 10000 masquerade
  }
}
''')
    server = subprocess.Popen(['nsenter', '-t', str(backend.pid), '-n', '--', sys.executable, '-u', '-c', '''
import socket
s=socket.socket(); s.bind(('0.0.0.0',10000)); s.listen(); print('ready',flush=True)
while True:
    c,_=s.accept(); c.sendall(b'backend'); c.close()
'''], stdout=subprocess.PIPE, text=True)
    children.append(server)
    assert server.stdout.readline().strip() == 'ready'

    def connect(process, address='10.255.0.11', port=1025, allowed=True):
        script = f'''
import socket
try:
    with socket.create_connection(({address!r},{port}),timeout=0.4) as c:
        success = c.recv(7) == b'backend'
except OSError:
    success = False
assert success == {allowed!r}, (success, {address!r}, {port})
'''
        if process:
            inside(process, sys.executable, '-c', script)
        else:
            run(sys.executable, '-c', script)

    connect(client)  # Reproduce the bypass before installing the actual guard.
    content = Path(sys.argv[1]).read_text()
    run('nft', '-f', '-', input='table inet mesh_ingress {\n' + content + '\n}\n')
    connect(client, allowed=False)
    connect(client, '192.0.2.1', 53)  # Deliberate physical DNS publication survives.
    connect(backend)  # br-mesh hairpin client survives.
    previous = 'physical'
    for interface in ('wg-mesh', 'docker0', 'br-ci-test'):
        run('ip', 'link', 'set', previous, 'name', interface)
        connect(client)
        previous = interface
    run('ip', 'link', 'set', previous, 'name', 'physical')
    connect(client, allowed=False)
    print('Mesh ingress checks passed: physical DNAT blocked; mesh/bridge clients and physical DNS preserved')
finally:
    for child in reversed(children):
        child.terminate()
        child.wait(timeout=5)
