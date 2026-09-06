#!/usr/bin/env python3
"""Exercise the actual updater script with fake Docker/systemd; no live changes."""
import os
from pathlib import Path
import re
import subprocess
import tempfile


source = (Path(__file__).resolve().parents[1] / "modules/profiles/containers/default.nix").read_text()
script = re.search(r"        script = ''\n(.*?)\n        '';", source, re.S)[1]
script = script.replace('${if cfg.pullOnly then "true" else "false"}', '$PULL_ONLY')
script = script.replace('${if cfg.restartChangedOnly then "true" else "false"}', '$CHANGED_ONLY')
script = script.replace('${skipContainersScript}', '$SKIP_CONTAINERS')
script = script.replace('${containerDefinitionsScript}', '$CONTAINER_ENTRIES').replace("''${", "${")
mock = r'''
docker() {
  printf 'docker %s\n' "$*" >> "$TRACE"
  case "$1 $2" in
    'pull '* ) [[ "$SCENARIO" != pull_failure ]] ;;
    'image inspect')
      [[ "$SCENARIO" != image_failure ]] || return 1
      [[ "$SCENARIO" == empty_image ]] || echo new-image ;;
    'container inspect')
      [[ "$SCENARIO" != container_failure ]] || return 1
      if [[ "$SCENARIO" == unchanged ]]; then echo new-image; else echo old-image; fi ;;
    *) return 99 ;;
  esac
}
systemctl() {
  printf 'systemctl %s\n' "$*" >> "$TRACE"
  case "$1" in
    cat) [[ "$SCENARIO" != missing_unit ]] ;;
    is-active) [[ "$SCENARIO" != inactive ]] ;;
    try-restart) [[ "$SCENARIO" != restart_failure ]] ;;
    *) return 99 ;;
  esac
}
'''
with tempfile.TemporaryDirectory(prefix="container-update-test-") as directory:
    trace = Path(directory) / "trace"

    def run(scenario, *, success=True, restarts=0, pull_only=False, changed_only=True, skip=""):
        trace.write_text("")
        result = subprocess.run(["bash", "-c", mock + script], capture_output=True, text=True, env={
            **os.environ, "TRACE": str(trace), "SCENARIO": scenario,
            "PULL_ONLY": str(pull_only).lower(), "CHANGED_ONLY": str(changed_only).lower(),
            "SKIP_CONTAINERS": skip,
            # Both containers share an image. Both must notice cached-image drift.
            "CONTAINER_ENTRIES": "first|shared:tag|docker-first\nsecond|shared:tag|docker-second.service",
        }, timeout=5)
        assert (result.returncode == 0) == success, (scenario, result.stdout, result.stderr)
        calls = trace.read_text()
        assert calls.count("systemctl try-restart") == restarts, (scenario, calls)
        return calls

    run("changed", restarts=2)
    run("unchanged")
    run("unchanged", changed_only=False, restarts=2)
    run("changed", pull_only=True)
    run("inactive")
    calls = run("changed", skip="first", restarts=1)
    assert "docker-first" not in calls
    for scenario in ("pull_failure", "image_failure", "empty_image", "container_failure", "missing_unit"):
        run(scenario, success=False)
    run("restart_failure", success=False, restarts=1)

print("Container updater checks passed: running-image drift, shared tags, stopped units and failures")
