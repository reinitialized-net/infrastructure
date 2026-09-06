#!/usr/bin/env python3
"""Exercise the generated firewall tool with a local fake curl; no network I/O."""

import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile


def mock_curl():
    args = sys.argv[2:]
    endpoint = args[-1].removeprefix("https://firewall.invalid:443")
    scenario = os.environ["FIREWALL_TEST_SCENARIO"]
    rule = json.loads(args[args.index("-d") + 1]).get("rule") if "-d" in args else None
    call = {
        "endpoint": endpoint,
        "insecure": "--insecure" in args,
        "http_errors": "--fail-with-body" in args,
        "rule": rule,
    }
    with open(os.environ["FIREWALL_TEST_CALLS"], "a") as log:
        log.write(json.dumps(call) + "\n")

    exit_code = 0
    if endpoint == "/api/core/menu/search":
        response = {"items": []}
        if scenario == "http_error":
            exit_code = 22 if call["http_errors"] else 0
        elif scenario == "certificate_error":
            exit_code = 60
    elif endpoint == "/api/diagnostics/interface/getInterfaceNames":
        response = {"igb0": "LAN"}
        if scenario == "discovery_error":
            response = {"status": "failed"}
    elif endpoint == "/api/firewall/filter/getInterfaceList":
        response = {"interfaces": {"items": [{"value": "lan", "label": "LAN"}]}}
        if scenario == "missing_mapping":
            response["interfaces"]["items"][0]["label"] = "OTHER"
    elif endpoint.endswith("&action=pass"):
        response = [
            {"interface": "igb0", "dir": "in", "protoname": "tcp", "src": "192.0.2.2", "dst": "198.51.100.2", "dstport": "443"},
            {"interface": "igb0", "dir": "in", "protoname": "udp", "src": "192.0.2.2", "dst": "198.51.100.3", "dstport": "53"},
        ]
        if scenario == "missing_log_field":
            del response[0]["dst"]
        elif scenario == "unknown_protocol":
            response[0]["protoname"] = "unexpected"
        elif scenario == "neighboring_source":
            response.append({**response[0], "src": "192.0.2.3"})
    elif endpoint.endswith("&action=block"):
        response = []
    elif endpoint == "/api/firewall/filter/savepoint":
        response = {"status": "ok", "revision": "123", "retention": "100"}
        if scenario == "no_savepoint":
            response = {"status": "error"}
            exit_code = 22
        elif scenario == "invalid_revision":
            response["revision"] = "../invalid"
        elif scenario == "low_retention":
            response["retention"] = "3"
    elif endpoint == "/api/firewall/filter/addRule":
        response = {"result": "saved", "uuid": "fake-rule-uuid"}
        if scenario == "allow_failure" and rule["action"] == "pass":
            response = {"result": "failed", "uuid": "must-not-count-as-success"}
        elif scenario == "deny_failure" and rule["action"] == "block":
            response = {"result": "failed"}
        elif scenario == "add_http_failure":
            exit_code = 22
    elif endpoint == "/api/firewall/filter/apply/123":
        response = {"status": "OK\n"}
        if scenario == "apply_failure":
            response = {"status": "not ok"}
        elif scenario == "apply_http_failure":
            exit_code = 22
    elif endpoint == "/api/firewall/filter/cancelRollback/123":
        response = {"status": "OK\n"}
        if scenario == "cancel_failure":
            response = {"status": "error"}
    elif endpoint == "/api/firewall/filter/revert/123":
        response = {"status": "ok"}
        if scenario == "revert_failure":
            response = {"status": "error"}
    else:
        raise AssertionError(f"Unexpected API call: {endpoint}")
    print(json.dumps(response))
    return exit_code


def run_tests():
    repo = Path(__file__).resolve().parents[1]
    source = (repo / "hosts/devenv/tools/update-network-firewall-rules.sh").read_text()
    packages = {"jq": "jq", "util-linux": "column", "coreutils": "sort", "gawk": "awk", "gnugrep": "grep", "gnused": "sed"}
    for package, command in packages.items():
        executable = shutil.which(command)
        if not executable:
            raise SystemExit(f"Required test command is missing: {command}")
        source = source.replace(f"@{package}@", str(Path(executable).resolve().parent.parent))
    for key, value in {"Host": "firewall.invalid", "Port": "443", "ApiKey": "mock-key", "ApiSecret": "mock-secret", "ApiSecretFile": ""}.items():
        source = source.replace(f"@secrets{key}@", value)

    with tempfile.TemporaryDirectory(prefix="firewall-test-") as temp:
        root = Path(temp)
        (root / "bin").mkdir()
        fake_curl = root / "bin/curl"
        fake_curl.write_text(f"#!{shutil.which('bash')}\nexec {shlex.quote(sys.executable)} {shlex.quote(str(Path(__file__).resolve()))} --mock-curl \"$@\"\n")
        fake_curl.chmod(0o755)
        script = root / "updateNetworkFirewallRules"
        script.write_text(source.replace("@curl@", str(root)))
        calls_file = root / "calls.jsonl"
        inherited_temp = root / "inherited-temp"
        inherited_temp.mkdir()

        def run(scenario="success", answer="yes\nkeep\n", dry_run=False, verify=None):
            calls_file.write_text("")
            env = {k: v for k, v in os.environ.items() if not k.startswith(("OPNSENSE_", "API_")) and k not in ("LOG_DAYS", "TOP_FLOWS", "BASH_ENV", "ENV")}
            env.update(FIREWALL_TEST_SCENARIO=scenario, FIREWALL_TEST_CALLS=str(calls_file), TMPDIR=str(inherited_temp))
            if verify is not None:
                env["OPNSENSE_VERIFY_TLS"] = verify
            result = subprocess.run([shutil.which("bash"), str(script)] + (["--dry-run"] if dry_run else []), input=answer, text=True, capture_output=True, env=env, timeout=15)
            calls = [json.loads(line) for line in calls_file.read_text().splitlines()]
            assert not list(inherited_temp.iterdir()), "Temporary files were not cleaned up"
            return result, calls

        def endpoints(calls):
            return [call["endpoint"] for call in calls]

        result, calls = run()
        assert result.returncode == 0, result.stdout + result.stderr
        assert all(call["http_errors"] and not call["insecure"] for call in calls)
        rules = [call["rule"] for call in calls if call["rule"]]
        assert len(rules) == 3 and [rule["action"] for rule in rules].count("pass") == 2
        assert {rule["source_net"] for rule in rules if rule["action"] == "pass"} == {"192.0.2.2"}
        assert "192.0.2.2" in result.stdout and "192.0.2.0/24" not in result.stdout
        assert endpoints(calls)[-1] == "/api/firewall/filter/cancelRollback/123"
        assert "/api/firewall/filter/revert/123" not in endpoints(calls)

        result, calls = run("neighboring_source")
        assert result.returncode == 0, result.stdout + result.stderr
        passes = [call["rule"] for call in calls if call["rule"] and call["rule"]["action"] == "pass"]
        assert len(passes) == 3
        assert {rule["source_net"] for rule in passes} == {"192.0.2.2", "192.0.2.3"}

        for verify in (None, "false"):
            result, calls = run(dry_run=True, verify=verify)
            assert result.returncode == 0, result.stdout + result.stderr
            assert all(call["insecure"] == (verify == "false") for call in calls)
            assert not any(call["rule"] for call in calls)
            assert not any("savepoint" in endpoint for endpoint in endpoints(calls))

        result, calls = run(verify="typo")
        assert result.returncode != 0 and not calls

        for scenario in ("http_error", "certificate_error", "discovery_error", "missing_mapping", "missing_log_field", "unknown_protocol", "no_savepoint", "invalid_revision", "low_retention"):
            result, calls = run(scenario)
            assert result.returncode != 0, (scenario, result.stdout, result.stderr)
            assert not any(call["rule"] for call in calls), scenario
            assert not any("/apply/" in endpoint or "cancelRollback" in endpoint for endpoint in endpoints(calls)), scenario

        for scenario in ("allow_failure", "deny_failure", "add_http_failure", "apply_failure", "apply_http_failure", "revert_failure"):
            result, calls = run(scenario, answer="yes\nno\n")
            assert result.returncode != 0, scenario
            assert endpoints(calls)[-1] == "/api/firewall/filter/revert/123", scenario
            assert not any("cancelRollback" in endpoint for endpoint in endpoints(calls)), scenario
            if scenario in ("allow_failure", "deny_failure", "add_http_failure"):
                assert not any("/apply/" in endpoint for endpoint in endpoints(calls)), scenario

        for answer in ("yes\n", "yes\nno\n"):
            result, calls = run(answer=answer)
            assert result.returncode != 0
            assert endpoints(calls)[-1] == "/api/firewall/filter/revert/123"
            assert not any("cancelRollback" in endpoint for endpoint in endpoints(calls))

        result, calls = run("cancel_failure")
        assert result.returncode != 0
        assert endpoints(calls)[-2:] == ["/api/firewall/filter/cancelRollback/123", "/api/firewall/filter/revert/123"]

    print("Firewall tool offline regression checks passed")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--mock-curl":
        sys.exit(mock_curl())
    run_tests()
