#!/usr/bin/env python3
"""Exercise promotion guards with local command doubles; no API or Nix builds."""
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import textwrap


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "hosts/devenv/infraAutoUpdate.nix").read_text()

# Release flake-show intentionally runs impure with a live overlay. Validation
# outputs must use a separate constructor, not extend that live configuration.
dual_export = (ROOT / "library/makeDualExport.nix").read_text()
validation_args = dual_export.split("validationArgs = nixosArgs // {", 1)[1].split("\n  };", 1)[0]
assert "includeSecrets = false;" in validation_args
assert "modules/secrets.example/${host}.nix" in validation_args
assert "validationSystem = makeConfiguration host validationArgs;" in dual_export
flake = (ROOT / "flake.nix").read_text()
checks = flake.split("checks.x86_64-linux =", 1)[1].split("packages =", 1)[0]
assert "dualSystems.${host}.validationSystem.config.system.build.toplevel" in checks
assert "getEnv" not in checks and "extendModules" not in checks
release = (ROOT / "hosts/devenv/tools/release-infra.sh").read_text()
assert "export INFRA_SECRETS_DIR" in release
assert "nix flake show path:. --no-write-lock-file --impure" in release


def functions(name):
    pattern = rf"(?m)^( +){name}\(\) ([{{(])\n.*?^\1[}})]$"
    return [textwrap.dedent(m.group()).replace("''${", "${")
            for m in re.finditer(pattern, SOURCE, re.S)]


def run(script, directory, **env):
    result = subprocess.run(
        ["bash", "-euo", "pipefail", "-c", script], cwd=directory,
        env={**os.environ, **env}, text=True, capture_output=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr


with tempfile.TemporaryDirectory() as temporary:
    work = Path(temporary)
    checkout = work / "checkout"
    (checkout / ".git").mkdir(parents=True)
    trace = work / "trace"
    log = work / "validation.log"
    # Unattended deploys may use only previously verified host identities.
    known_hosts = functions("require_known_hosts")[0].replace('$HOME', '$test_home')
    trust_setup = f"""
test_home={shlex.quote(str(work / 'ssh-test'))}
deploy_host_ips='192.0.2.2 192.0.2.3'
ssh-keygen() {{ [[ "$2" != "$UNTRUSTED_HOST" ]]; }}
ssh-keyscan() {{ echo 'unverified key enrollment attempted'; exit 98; }}
"""
    run(trust_setup + known_hosts + '\nrequire_known_hosts', work, UNTRUSTED_HOST="none")
    for untrusted in ("192.0.2.2", "192.0.2.3"):
        run(trust_setup + known_hosts + '\nif require_known_hosts; then exit 98; fi',
            work, UNTRUSTED_HOST=untrusted)
    assert (work / 'ssh-test/.ssh/known_hosts').read_text() == ''
    setup = f"""set -euo pipefail
checkout_dir={shlex.quote(str(checkout))}
trace={shlex.quote(str(trace))}
repo_clone_url=unused
default_branch=indev
secrets_dir={shlex.quote(str(work))}
git() {{
  printf '%s\\n' "$*" >> "$trace"
  if [[ " $* " == *" $FAIL "* ]]; then return 1; fi
  if [[ " $* " == *' rev-parse '* ]]; then printf '%s\\n' "$ACTUAL_HEAD"; fi
}}
"""
    # Each workflow uses ensure_checkout in an if condition: every failed Git
    # operation must prevent later destructive checkout operations.
    checkouts = functions("ensure_checkout")
    assert len(checkouts) == 3
    for function in checkouts:
        for failed in ("fetch", "checkout", "reset", "clean"):
            trace.write_text("")
            run(setup + function + "\nif ensure_checkout; then exit 90; fi\n",
                work, FAIL=failed, ACTUAL_HEAD="a" * 40)
            commands = trace.read_text().splitlines()
            assert failed in commands[-1], commands
            assert not any(" clean " in f" {c} " for c in commands) or failed == "clean"

    validate = functions("validate_pr")[0]
    doubles = """
require_secrets_dir() { [[ "$FAIL" != secrets ]]; }
jq() { [[ "$FAIL" != json ]]; }
nix() {
  [[ ! -v INFRA_SECRETS_DIR && ! -v GIT_PASSWORD && ! -v GIT_ASKPASS ]] || return 99
  printf '%s\\n' "$*" >> "$trace"
  [[ "$FAIL" != "$1" ]]
}
bash() { printf '%s\\n' syntax >> "$trace"; [[ "$FAIL" != syntax ]]; }
"""
    call = f'validate_pr 12 renovate/dependency {"a" * 40} {shlex.quote(str(log))}'
    for failed in ("fetch", "checkout", "json", "flake", "build", "syntax"):
        trace.write_text("")
        run(setup + doubles + validate + f"\nif {call}; then exit 91; fi\n",
            work, FAIL=failed, ACTUAL_HEAD="a" * 40)
        if failed != "syntax":
            assert "syntax" not in trace.read_text(), (failed, trace.read_text())

    trace.write_text("")
    run(setup + doubles + validate + f"\nif {call}; then exit 92; fi\n",
        work, FAIL="never", ACTUAL_HEAD="b" * 40)
    assert "--detach" not in trace.read_text()
    trace.write_text("")
    run(setup + doubles + validate + f"\n{call}\n", work,
        FAIL="never", ACTUAL_HEAD="a" * 40,
        INFRA_SECRETS_DIR="/synthetic-forbidden-overlay",
        GIT_PASSWORD="synthetic-credential", GIT_ASKPASS="/synthetic-askpass")
    build = next(line for line in trace.read_text().splitlines() if line.startswith("build "))
    for host in ("devenv", "rp1", "apps1", "apps2", "apps3", "ai1", "db1"):
        assert f"path:.#checks.x86_64-linux.{host}" in build, build
    assert "nixosConfigurations" not in build
    assert "modules/secrets" not in validate
    assert not (checkout / "modules").exists()
    assert "--option restrict-eval true" in validate
    assert "--impure" not in validate
    assert 'unset INFRA_SECRETS_DIR GIT_PASSWORD GIT_ASKPASS' in validate

    # Approval must be active, human, by a writer and tied to the validated head.
    approval = functions("has_manual_approval")[0]
    approve_setup = """
forgejo_username=Infratainer
repo_owner=owner
repo_name=repo
api() {
  case "$2" in
    */permission) printf '{"permission":"%s"}\\n' "${PERMISSION:-write}" ;;
    *'reviews?page=1&limit=50') printf '%s\\n' "$REVIEWS" ;;
    *'reviews?page=2&limit=50')
      [[ "${REVIEW_PAGE_TWO_FAIL:-false}" != true ]] || return 1
      printf '%s\\n' "${REVIEW_PAGE_TWO-[]}"
      ;;
    *'reviews?page=3&limit=50') printf '[]\\n' ;;
    *) return 1 ;;
  esac
}
"""
    review = {"user": {"login": "maintainer"}, "official": True,
              "state": "APPROVED", "commit_id": "a" * 40,
              "submitted_at": "2026-09-01T00:00:00Z"}
    for change in ({"commit_id": ""},
                   {"commit_id": "b" * 40}, {"dismissed": True},
                   {"stale": True}, {"user": {"login": "Infratainer"}}):
        run(approve_setup + approval + f'\nif has_manual_approval 12 {"a" * 40}; then exit 93; fi',
            work, REVIEWS=json.dumps([{**review, **change}]))
    run(approve_setup + approval + f'\nhas_manual_approval 12 {"a" * 40}',
        work, REVIEWS=json.dumps([review]))
    run(approve_setup + approval + f'\nif has_manual_approval 12 {"a" * 40}; then exit 93; fi',
        work, REVIEWS=json.dumps([review]), PERMISSION="read")
    for state, success in (("COMMENTED", True), ("REQUEST_CHANGES", False)):
        reviews = [review, {**review, "state": state,
                            "submitted_at": "2026-09-02T00:00:00Z"}]
        check = f'has_manual_approval 12 {"a" * 40}'
        if not success:
            check = f"if {check}; then exit 94; fi"
        run(approve_setup + approval + "\n" + check, work, REVIEWS=json.dumps(reviews))

    # Approval decisions include all pages, even when the server returns fewer
    # rows than requested. Stop only at an empty page, not a short page.
    later_review = {**review, "submitted_at": "2026-09-02T00:00:00Z"}
    blocked = f'if has_manual_approval 12 {"a" * 40}; then exit 97; fi'
    for state in ("REQUEST_CHANGES", "CHANGES_REQUESTED", "REQUESTED_CHANGES"):
        run(approve_setup + approval + "\n" + blocked, work,
            REVIEWS=json.dumps([review]),
            REVIEW_PAGE_TWO=json.dumps([{**later_review, "state": state}]))
    run(approve_setup + approval + f'\nhas_manual_approval 12 {"a" * 40}', work,
        REVIEWS=json.dumps([{**review, "state": "REQUEST_CHANGES"}]),
        REVIEW_PAGE_TWO=json.dumps([later_review]))

    # A good first page cannot authorize merging when any later page fails or
    # is malformed. Also reject malformed initial responses and JSON streams.
    run(approve_setup + approval + "\n" + blocked, work,
        REVIEWS=json.dumps([review]), REVIEW_PAGE_TWO_FAIL="true")
    for malformed in ('{"message":"error"}', "null", "invalid JSON", "", '{}\n[]'):
        run(approve_setup + approval + "\n" + blocked, work, REVIEWS=malformed)
        run(approve_setup + approval + "\n" + blocked, work,
            REVIEWS=json.dumps([review]), REVIEW_PAGE_TWO=malformed)

    # A conflict/rejected merge must never trigger a retry without the SHA guard.
    merge = functions("merge_pr")[0]
    payload = work / "payload"
    merge_setup = f"""
repo_owner=owner
repo_name=repo
api() {{
  printf '%s\\n' "$3" >> {shlex.quote(str(payload))}
  return 1
}}
"""
    run(merge_setup + merge + f'\nif merge_pr 12 "Update dependency" {"a" * 40}; then exit 95; fi', work)
    payloads = json.loads(payload.read_text())
    assert payloads["head_commit_id"] == "a" * 40
    assert payloads["Do"] == "merge"

    # An unrelated build failure must not restart a healthy production bus.
    for name in ("rebuild-host.sh", "update-infra.sh"):
        tool = (ROOT / "hosts/devenv/tools" / name).read_text()
        recovery = re.search(r"ssh [^\n']+ '([^']+)'", tool).group(1)
        for healthy in ("yes", "no"):
            trace.write_text("")
            mocked = f"""
sudo() {{
  if [[ "$1" == busctl ]]; then
    [[ "$HEALTHY" != yes ]] || echo org.freedesktop.systemd1
  else
    printf '%s\\n' "$*" >> {shlex.quote(str(trace))}
  fi
}}
sleep() {{ :; }}
"""
            check = f"( {recovery} )"
            if healthy == "yes":
                check = f"if {check}; then exit 96; fi"
            run(mocked + check, work, HEALTHY=healthy)
            assert bool(trace.read_text()) == (healthy == "no")

print("Promotion regression checks passed (failed steps, moved heads, approvals, merge guard).")
