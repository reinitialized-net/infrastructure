#!/usr/bin/env python3
"""Check target selection in the built devenv tools without deploying anything.

Usage: python3 tests/check-deployment-targets.py /nix/store/...-nixos-system-devenv-...
"""
from pathlib import Path
import re
import sys


tools = Path(sys.argv[1]) / 'sw/bin'


def hosts(tool):
    script = (tools / tool).read_text()
    return set(re.search(r'^\s*VALID_HOSTS="([^"]+)"', script, re.M)[1].split())


fleet = {'devenv', 'rp1', 'apps1', 'apps2', 'apps3', 'llm1', 'db1'}
assert hosts('updateInfra') == fleet
assert hosts('rebuildHost') == fleet
assert hosts('releaseInfra') == fleet
deploy = (tools / 'infra-deploy').read_text()
addresses = set(re.search(r'^\s*deploy_host_ips="([^"]+)"', deploy, re.M)[1].split())
assert addresses == {'10.1.12.2', '10.1.11.2', '10.1.11.3', '10.1.11.4', '10.1.11.9', '10.1.11.11'}
assert 'ssh-keyscan ' not in deploy
print('Deployment targets passed: every exported fleet host is a bulk, explicit and release target')
