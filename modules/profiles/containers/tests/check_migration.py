#!/usr/bin/env python3
"""Offline regression check: all Docker, SSH, sudo and systemd calls are mocked."""

import json
import os
from pathlib import Path
import runpy
import shlex
import shutil
import subprocess
import sys
import tempfile


TOOLS = Path(__file__).resolve().parents[1] / "tools"


def executable(name):
    system = Path("/run/current-system/sw/bin") / name
    return system if system.exists() else Path(shutil.which(name))


def substitute(source, values):
    for name, value in values.items():
        source = source.replace(f"@{name}@", str(value))
    return source


with tempfile.TemporaryDirectory(prefix="migration-regression-") as directory:
    root = Path(directory)
    state_path = root / "state.json"
    events_path = root / "events.jsonl"
    services = root / "services.json"
    services.write_text(json.dumps({
        f"{side}-{name}": {"unit": f"custom-{side}-{name}.service", "dependsOn": [] if name == "running" else [f"{side}-running"]}
        for side in ("local", "remote") for name in ("running", "dependent", "stopped-dependent")
    }))
    coreutils = executable("dirname").resolve().parents[1]
    values = {
        "python": Path(sys.executable).parents[1],
        "coreutils": coreutils,
        "gawk": executable("awk").resolve().parents[1],
        "gnugrep": executable("grep").resolve().parents[1],
        "containerServicesFile": services,
        "dockerConfig": root / "immutable-config",
        "migrationSshConfig": root / "ssh-config",
    }
    # The dispatcher embeds its temporary state path. It never invokes host services.
    dispatcher = root / "dispatcher.py"
    dispatcher.write_text(f"#!{sys.executable}\n" + r'''
import json, os, pathlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parent
side = pathlib.Path(sys.argv[0]).parent.parent.name
tool = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
if tool == "sudo":
    if args[:2] == ["-u", "docker"]: args = args[2:]
    if args[:1] == ["-n"]: args = args[1:]
    os.execv(args[0], args)
if tool == "ssh":
    env = dict(os.environ, SSH_ORIGINAL_COMMAND=args[-1])
    sys.exit(subprocess.run([sys.executable, str(root / "remote/helper")], env=env).returncode)
with open(root / "events.jsonl", "a") as events:
    events.write(json.dumps([side, tool, *args]) + "\n")
state = json.loads((root / "state.json").read_text())
scenario = state["scenario"]
def save(): (root / "state.json").write_text(json.dumps(state))
if tool == "systemctl":
    action, unit = args
    services = json.loads((root / "services.json").read_text())
    name = next(name for name, service in services.items() if service["unit"] == unit)
    if action == "stop" and scenario == "stop_failure": sys.exit(1)
    state[side][name] = action == "start"
    if action == "stop" and name.endswith("-running"):
        # Model systemd Requires= stop propagation to a consumer of another volume.
        state[side][side + "-dependent"] = False
    # systemd start recreates a container that --rm removed during stop.
    state[side + "_exists"] = action == "start"
    save()
elif tool == "docker":
    if args[0] == "ps":
        if side == "remote" and scenario == "discovery_failure": sys.exit(1)
        if side == "remote" and scenario == "post_stop_discovery_failure" and not state["remote_exists"]: sys.exit(1)
        running = [name for name, active in state[side].items() if active]
        if "--filter" in args: running = [name for name in running if name.endswith("-running")]
        if running: print("\n".join(running))
    elif args[:2] == ["image", "inspect"] or args[:2] in (["volume", "inspect"], ["volume", "create"]):
        print("[]")
    elif args[0] == "inspect":
        print("true" if args[-1] == "manual-autoremove" else "false")
    elif args[0] in ("stop", "start"):
        name = args[-1]
        if name in ("local-running", "remote-running"):
            # Model the old bug: Docker start cannot recreate a removed OCI container.
            if args[0] == "start" and not state[side + "_exists"]: sys.exit(1)
            if args[0] == "stop": state[side + "_exists"] = False
        state[side][name] = args[0] == "start"
        save()
    elif args[0] == "run":
        text = " ".join(args)
        if "find /volume" in text:
            print("2" if side == "remote" and scenario == "count_mismatch" else "1")
        elif "tar tf -" in text:
            if scenario == "bad_archive": sys.exit(1)
        elif "tar xf" in text:
            if "-i" in args: sys.stdin.buffer.read()
            state[side + "_written"] = True
            save()
            if scenario in ("stream_failure", "import_failure"): sys.exit(9)
        elif "tar cf" in text:
            mounts = [args[i+1] for i, arg in enumerate(args[:-1]) if arg == "-v"]
            staging = next((mount[:-9] for mount in mounts if mount.endswith(":/staging")), None)
            if staging:
                target = next(arg for arg in args if arg.startswith("/staging/"))
                pathlib.Path(staging, pathlib.Path(target).name).write_bytes(b"new archive")
                if scenario == "export_failure": sys.exit(7)
            else:
                sys.stdout.buffer.write(b"archive stream")
                if scenario == "source_stream_failure": sys.exit(7)
        else:
            raise AssertionError(args)
    else:
        raise AssertionError(args)
else:
    raise AssertionError(tool)
''')
    dispatcher.chmod(0o755)
    for side in ("local", "remote"):
        package = root / side
        (package / "bin").mkdir(parents=True)
        for tool in ("docker", "ssh", "sudo", "systemctl"):
            (package / "bin" / tool).symlink_to(dispatcher)
        rendered = substitute((TOOLS / "docker-migration-command.py").read_text(), {
            **values, "docker": package, "systemd": package, "openssh": package,
        }).replace("/run/wrappers/bin/sudo", str(package / "bin/sudo"))
        (package / "helper").write_text(rendered)
        (package / "helper").chmod(0o755)
        (package / "bin/docker-migration-command").symlink_to(package / "helper")

    validator = runpy.run_path(str(root / "local/helper"))
    parse = lambda text: validator["command_argv"](shlex.split(text))
    for command in (
        "docker stop local-running", "docker start local-running",
        "docker migration-plan target", "docker migration-plan target local-running",
        "docker volume create target", "docker volume inspect target",
        "docker ps --filter volume=target --format '{{.Names}}'",
        "docker run --rm -i -v target:/volume alpine sh -c 'gunzip | tar xf - -C /volume'",
        "docker run --rm -v target:/volume:ro alpine sh -c 'find /volume -type f | wc -l'",
        "sftp-server", "scp -r -t '/home/docker/file with spaces'", "scp -f /home/docker/file", "scp -v -t ~/upload",
        "scp -t -- -filename", "scp -f -- /home/docker/file",
    ):
        assert parse(command), command
    for command in (
        "docker ps; id", "docker exec app sh", "docker run --privileged alpine sh",
        "docker run --rm -i -v /:/volume alpine sh -c 'gunzip | tar xf - -C /volume'",
        "docker run --rm -i -v target:/volume alpine sh -c 'gunzip | tar xf - -C /volume; id'",
        "docker volume create --opt=device=/ target", "docker -H tcp://attacker ps",
        "scp -S /bin/sh -t /tmp/file", "scp -t /tmp/file extra", "sftp-server -e; id",
        "docker start 'app; id'", "docker$(id) ps", "scp -t -f /tmp/file",
    ):
        try:
            parse(command)
        except ValueError:
            pass
        else:
            raise AssertionError(f"accepted forbidden command: {command}")
    for program in ("cat", "gunzip", "bunzip2", "apk add --no-cache xz > /dev/null 2>&1 && unxz"):
        argv = parse(f"docker run --rm -i -v target:/volume alpine sh -c '{program} | tar xf - -C /volume'")
        assert ["sh", "-eu", "-o", "pipefail", "-c"] == argv[-6:-1]
    assert parse("scp -t ~/upload")[-1] == "/home/docker/upload"

    key = root / "identity"
    key.write_text("test fixture; not a key")
    script = root / "migrate-volumes"
    script.write_text(substitute((TOOLS / "migrate-volumes.sh").read_text(), {
        **values, "docker": root / "local", "openssh": root / "local", "migrationCommand": root / "local",
    }).replace("/run/wrappers/bin/sudo", str(root / "local/bin/sudo"))
      .replace("/var/lib/docker-volume-migration/identity", str(key)))
    backup = root / "input archive.tar.bz2"
    backup.write_bytes(b"offline mock archive")
    output = root / "backups"
    output.mkdir()

    def run(scenario, *args, success):
        state_path.write_text(json.dumps({
            "scenario": scenario,
            "local": {"local-running": True, "local-dependent": True, "local-stopped-dependent": False, "already-stopped": False},
            "remote": {"remote-running": True, "remote-dependent": True, "remote-stopped-dependent": False, "already-stopped": False},
            "local_exists": True, "remote_exists": True,
        }))
        events_path.write_text("")
        result = subprocess.run([str(executable("bash")), str(script), *args], capture_output=True, text=True)
        assert (result.returncode == 0) == success, (scenario, result.stdout, result.stderr)
        events = [json.loads(line) for line in events_path.read_text().splitlines()]
        assert not any(event[1] == "systemctl" and "already-stopped" in event[-1] for event in events)
        state = json.loads(state_path.read_text())
        assert not state["local"]["already-stopped"] and not state["remote"]["already-stopped"]
        for side in ("local", "remote"):
            assert not state[side][side + "-stopped-dependent"]
            assert state[side][side + "-dependent"] == state[side][side + "-running"], (scenario, state)
        return state, events

    transfer = ("transfer", "-v", "source", "-V", "target", "-r", "mock-host")
    state, _ = run("success", *transfer, success=True)
    assert not state["local"]["local-running"] and state["remote"]["remote-running"]
    run("success", *transfer, "-c", "local-running", "-C", "remote-running", success=True)
    for scenario in ("stream_failure", "source_stream_failure", "count_mismatch"):
        state, _ = run(scenario, *transfer, success=False)
        assert state["local"]["local-running"] and not state["remote"]["remote-running"]
    for scenario in ("discovery_failure", "post_stop_discovery_failure", "stop_failure"):
        state, events = run(scenario, *transfer, success=False)
        assert not state.get("remote_written")
        assert state["local"]["local-running"] and state["remote"]["remote-running"]
        if scenario == "discovery_failure": assert not any(e[1] == "systemctl" for e in events)
    for scenario in ("bad_archive", "checksum_failure"):
        checksum = Path(str(backup) + ".sha256")
        if scenario == "checksum_failure": checksum.write_text("bad checksum")
        state, events = run(scenario, "import", "-v", "target", "-f", str(backup), success=False)
        assert not any(e[1] == "systemctl" for e in events)
        checksum.unlink(missing_ok=True)
    state, _ = run("import_failure", "import", "-v", "target", "-f", str(backup), success=False)
    assert not state["local"]["local-running"]
    state, events = run("success", "import", "-v", "target", "-f", str(backup), success=True)
    assert state["local"]["local-running"] and any("bunzip2" in " ".join(e) for e in events)
    previous = output / "source.tar"
    previous.write_bytes(b"previous verified backup")
    state, _ = run("export_failure", "export", "-v", "source", "-d", str(output), "-z", "none", success=False)
    assert state["local"]["local-running"] and previous.read_bytes() == b"previous verified backup"
    state, _ = run("success", "export", "-v", "source", "-d", str(output), success=True)
    assert state["local"]["local-running"]
    assert (output / "source.tar.gz.sha256").exists()
    assert not list(output.glob(".migration-backup.*"))

    for name, allowed in (("manual", True), ("manual-autoremove", False)):
        result = subprocess.run([sys.executable, str(root / "local/helper"), "docker", "stop", name], capture_output=True)
        assert (result.returncode == 0) == allowed

print("Migration command restrictions and recovery checks passed (no live Docker/SSH/systemd calls).")
