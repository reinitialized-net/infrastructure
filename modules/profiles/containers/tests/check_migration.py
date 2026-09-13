#!/usr/bin/env python3
"""Offline regression check: all Docker, SSH, sudo and systemd calls are mocked."""

import hashlib
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
    state = json.loads((root / "state.json").read_text())
    if state["scenario"] in ("unknown_host", "changed_host"):
        sys.exit(255)
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

    # Inspect OpenSSH's effective configuration without opening a connection.
    config_source = (TOOLS.parent / "containerTools.nix").read_text()
    ssh_config = config_source.split('migrationSshConfig = pkgs.writeText "docker-migration-ssh-config"', 1)[1].split("\n", 1)[1].split("'';", 1)[0]
    values["migrationSshConfig"].write_text(ssh_config)
    effective = subprocess.run([str(executable("ssh")), "-G", "-F", str(values["migrationSshConfig"]), "fixture.invalid"],
                               capture_output=True, text=True, check=True).stdout
    settings = dict(line.split(" ", 1) for line in effective.splitlines())
    assert settings["stricthostkeychecking"] == "true"
    assert settings["userknownhostsfile"] == "/var/lib/docker-volume-migration/known_hosts"
    assert settings["globalknownhostsfile"] == "/dev/null"
    assert settings["updatehostkeys"] == "false"

    # Exercise trust-file provisioning with temporary data. Ownership-changing
    # commands are mocked; real replacement, symlink and mode behavior is tested.
    provisioning = (TOOLS.parent / "default.nix").read_text().split("          # Only administrator-provisioned trust", 1)[1].split("        '';", 1)[0]
    provisioning = "# Only administrator-provisioned trust" + provisioning
    ownership_tools = root / "ownership-tools"
    ownership_tools.mkdir()
    (ownership_tools / "chown").write_text("#!/bin/sh\nexit 0\n")
    (ownership_tools / "stat").write_text("#!/bin/sh\nprintf '%s\\n' \"$FIXTURE_TRUST_OWNER\"\n")
    for tool in ownership_tools.iterdir(): tool.chmod(0o755)
    trust_directory = root / "trust"
    trust_directory.mkdir()
    trusted_hosts = trust_directory / "known_hosts"
    trust_sentinel = root / "trust-sentinel"
    trust_sentinel.write_text("must not change")
    for kind in ("missing", "untrusted", "symlink", "writable", "verified"):
        trusted_hosts.unlink(missing_ok=True)
        if kind == "symlink":
            trusted_hosts.symlink_to(trust_sentinel)
        elif kind != "missing":
            trusted_hosts.write_text("fixture verified keys" if kind == "verified" else "untrusted keys")
            trusted_hosts.chmod(0o666 if kind == "writable" else 0o640)
        result = subprocess.run([str(executable("bash")), "-eu", "-c", 'state_dir=$1; key_tmp=""; ' + provisioning, "fixture", str(trust_directory)],
            env={**os.environ, "PATH": str(ownership_tools) + os.pathsep + os.environ["PATH"],
                 "FIXTURE_TRUST_OWNER": "1000" if kind == "untrusted" else "0"}, capture_output=True, text=True)
        assert result.returncode == 0, (kind, result.stderr)
        assert not trusted_hosts.is_symlink()
        assert trusted_hosts.read_text() == ("fixture verified keys" if kind == "verified" else "")
        assert trusted_hosts.stat().st_mode & 0o777 == 0o640
        assert trust_sentinel.read_text() == "must not change"
        assert not list(trust_directory.glob(".known-hosts.*"))

    # Some test sandboxes map root-owned /tmp to nobody. Normalize only these
    # fixture ancestors; production directory ownership checks remain unchanged.
    stat_fixture = root / "stat"
    stat_fixture.write_text(f"#!{sys.executable}\n" +
        "import json, pathlib, subprocess, sys\n" +
        f"result = subprocess.run([{str(coreutils / 'bin/stat')!r}, *sys.argv[1:]], capture_output=True, text=True)\n" +
        "output = result.stdout\n" +
        "if sys.argv[-1] in ('/', '/tmp') and result.returncode == 0: output = '0 ' + output.split(' ', 1)[1]\n" +
        f"if sys.argv[-1] == {str(root / 'raced-output')!r} and json.loads(pathlib.Path({str(state_path)!r}).read_text())['scenario'] == 'mkdir_owner_race': output = '12345 ' + output.split(' ', 1)[1]\n" +
        "sys.stdout.write(output)\nsys.stderr.write(result.stderr)\nsys.exit(result.returncode)\n")
    stat_fixture.chmod(0o755)

    transfer_root = root / "transfer-root"
    transfer_root.mkdir()
    race_trusted_target = root / "race-trusted-target"
    race_trusted_target.mkdir()
    mkdir_fixture = root / "mkdir"
    mkdir_fixture.write_text(f"#!{sys.executable}\n" +
        "import json, os, pathlib, sys\n" +
        f"scenario = json.loads(pathlib.Path({str(state_path)!r}).read_text())['scenario']\n" +
        "target = pathlib.Path(sys.argv[-1])\n" +
        "if scenario in ('mkdir_shared_race', 'mkdir_owner_race'):\n    target.mkdir()\n    target.chmod(0o777 if scenario == 'mkdir_shared_race' else 0o755)\n" +
        f"elif scenario == 'mkdir_symlink_race': target.symlink_to({str(transfer_root)!r}, target_is_directory=True)\n" +
        f"elif scenario == 'mkdir_trusted_symlink_race': target.symlink_to({str(race_trusted_target)!r}, target_is_directory=True)\n" +
        f"os.execv({str(coreutils / 'bin/mkdir')!r}, [{str(coreutils / 'bin/mkdir')!r}, *sys.argv[1:]])\n")
    mkdir_fixture.chmod(0o755)
    key = root / "identity"
    key.write_text("test fixture; not a key")
    script = root / "migrate-volumes"
    script.write_text(substitute((TOOLS / "migrate-volumes.sh").read_text(), {
        **values, "docker": root / "local", "openssh": root / "local", "migrationCommand": root / "local",
    }).replace("/run/wrappers/bin/sudo", str(root / "local/bin/sudo"))
      .replace("/var/lib/docker-volume-migration/identity", str(key))
      .replace(str(coreutils / "bin/stat"), str(stat_fixture))
      .replace(str(coreutils / "bin/mkdir"), str(mkdir_fixture))
      .replace("/home/docker", str(transfer_root)))
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
    for scenario in ("unknown_host", "changed_host", "discovery_failure", "post_stop_discovery_failure", "stop_failure"):
        state, events = run(scenario, *transfer, success=False)
        assert not state.get("remote_written")
        assert state["local"]["local-running"] and state["remote"]["remote-running"]
        if scenario in ("unknown_host", "changed_host", "discovery_failure"):
            assert not any(e[1] == "systemctl" for e in events)
            assert not any(e[1] == "docker" and e[2] == "run" for e in events)
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

    # Attacker-controlled final names must never redirect writes outside backups.
    sentinel = root / "sentinel"
    sentinel.write_bytes(b"must remain unchanged")
    target_directory = root / "outside-directory"
    target_directory.mkdir()
    archive = output / "source.tar.gz"
    sidecar = output / "source.tar.gz.sha256"
    for target in (sentinel, root / "missing-target", target_directory):
        for destination in (archive, sidecar):
            destination.unlink(missing_ok=True)
            destination.symlink_to(target)
            run("success", "export", "-v", "source", "-d", str(output), success=True)
            assert not destination.is_symlink()
            assert archive.stat().st_mode & 0o777 == 0o600
            assert sidecar.stat().st_mode & 0o777 == 0o600
            assert sentinel.read_bytes() == b"must remain unchanged"
            assert not (root / "missing-target").exists()
            assert not list(target_directory.iterdir())
            assert sidecar.read_text().strip() == hashlib.sha256(archive.read_bytes()).hexdigest()
    sidecar.unlink()
    sidecar.symlink_to(sentinel)
    run("success", "export", "-v", "source", "-d", str(output), "-k", success=True)
    assert not sidecar.exists() and not sidecar.is_symlink()
    assert sentinel.read_bytes() == b"must remain unchanged"

    # A shared destination or replaceable ancestor is rejected before downtime.
    for shared in (output, root):
        original_mode = shared.stat().st_mode & 0o7777
        shared.chmod(0o777)
        try:
            state, events = run("success", "export", "-v", "source", "-d", str(output), success=False)
            assert not any(e[1] == "systemctl" or (e[1] == "docker" and e[2] == "run") for e in events)
        finally:
            shared.chmod(original_mode)

    transfer_alias = root / "transfer-alias"
    transfer_alias.symlink_to(transfer_root, target_is_directory=True)
    for exposed in (transfer_root, transfer_root / "new-child", transfer_alias / "new-child"):
        _, events = run("success", "export", "-v", "source", "-d", str(exposed), success=False)
        assert not any(e[1] == "systemctl" or (e[1] == "docker" and e[2] == "run") for e in events)
        assert not (transfer_root / "new-child").exists()

    # Inject an attacker-created child after the initial ancestry check.
    raced_output = root / "raced-output"
    for scenario in ("mkdir_shared_race", "mkdir_owner_race", "mkdir_symlink_race", "mkdir_trusted_symlink_race"):
        _, events = run(scenario, "export", "-v", "source", "-d", str(raced_output), success=False)
        assert not any(e[1] == "systemctl" or (e[1] == "docker" and e[2] == "run") for e in events)
        assert not list(raced_output.iterdir())
        if raced_output.is_symlink(): raced_output.unlink()
        else: raced_output.rmdir()

    # Failure publishing metadata preserves the existing archive and resumes consumers.
    sidecar.mkdir()
    prior_archive = archive.read_bytes()
    state, _ = run("success", "export", "-v", "source", "-d", str(output), success=False)
    assert archive.read_bytes() == prior_archive
    assert state["local"]["local-running"]
    sidecar.rmdir()
    assert not list(output.glob(".migration-backup.*"))

    for name, allowed in (("manual", True), ("manual-autoremove", False)):
        result = subprocess.run([sys.executable, str(root / "local/helper"), "docker", "stop", name], capture_output=True)
        assert (result.returncode == 0) == allowed

print("Migration command restrictions and recovery checks passed (no live Docker/SSH/systemd calls).")
