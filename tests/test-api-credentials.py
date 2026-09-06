#!/usr/bin/env python3
"""Verify real API helpers pass authentication through a file descriptor."""
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import textwrap


root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="api-credential-test-") as temporary:
    work = Path(temporary)
    curl = work / "curl"
    curl.write_text(f"#!{sys.executable}\n" + '''
import os, pathlib, sys
args = sys.argv[1:]
token = os.environ['TEST_API_TOKEN']
assert all(token not in arg for arg in args), 'credential exposed in argv'
headers = [args[i + 1] for i, arg in enumerate(args[:-1]) if arg in ('-H', '--header')]
authorization = [pathlib.Path(header[1:]).read_text() for header in headers if header.startswith('@')]
assert authorization == ['Authorization: token ' + token + '\\n'], 'incorrect authentication header'
print('{}')
''')
    curl.chmod(0o755)
    token = "audit-test-token-with-'literal-characters"
    env = {**os.environ, "TEST_API_TOKEN": token, "PATH": str(work) + os.pathsep + os.environ["PATH"]}
    count = 0
    for name in ("hosts/devenv/infraAutoUpdate.nix", "library/infraUpdateReport.nix"):
        source = (root / name).read_text()
        for match in re.finditer(r"(?m)^( +)api\(\) \{\n.*?^\1\}", source, re.S):
            function = textwrap.dedent(match[0]).replace("''${", "${")
            setup = 'token="$TEST_API_TOKEN"\napi_root=http://unused.invalid\n'
            # Exercise GET and both payload branches; the fake curl cannot use the network.
            script = setup + function + '\napi GET /test\napi POST /test payload\n'
            result = subprocess.run([shutil.which("bash"), "-euc", script], env=env, text=True, capture_output=True)
            assert result.returncode == 0, (name, result.stderr)
            count += 1
    assert count == 3, count
    runner = (root / "hosts/apps2.nix").read_text()
    command = re.search(r'HTTP_STATUS=\$\((curl .*?"\$FORGEJO_INSTANCE_URL/api/v1/admin/runners/\$RUNNER_ID")\)', runner, re.S)[1]
    result = subprocess.run([shutil.which("bash"), "-euc", command], env={
        **env, "FORGEJO_ADMIN_TOKEN": token, "FORGEJO_INSTANCE_URL": "http://unused.invalid", "RUNNER_ID": "42",
    }, text=True, capture_output=True)
    assert result.returncode == 0, result.stderr
print("API credential checks passed: all four callers preserve headers without bearer tokens in argv")
