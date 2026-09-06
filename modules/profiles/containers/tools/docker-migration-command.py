#!@python@/bin/python3 -I
"""Execute the small command vocabulary used by Docker volume migration."""

import json
import os
import re
import shlex
import subprocess
import sys


DOCKER = "@docker@/bin/docker"
SYSTEMCTL = "@systemd@/bin/systemctl"
SERVICES = json.load(open("@containerServicesFile@", encoding="utf-8"))
ENV = {
    "PATH": "@docker@/bin:@openssh@/bin:@coreutils@/bin",
    "HOME": "/home/docker",
    "DOCKER_CONFIG": "@dockerConfig@",
    "DOCKER_HOST": "unix:///var/run/docker.sock",
    "LANG": "C.UTF-8",
}
TRANSFER_DIRECTORIES = ("/home/docker", "/var/lib/docker/volumes/.migration-staging")


def transfer_argv(command):
    """Confine SCP/SFTP, including protocol paths and symlinks, to transfer data.

    Bind only OpenSSH's runtime closure, never the whole store or host root.
    A missing/inaccessible staging directory stays unavailable; no permission
    changes are made to Docker's data tree. Sandbox setup failures deny access.
    """
    sandbox = ["@bubblewrap@/bin/bwrap", "--unshare-all", "--die-with-parent",
               "--new-session", "--cap-drop", "ALL", "--dev", "/dev"]
    with open("@transferClosure@", encoding="utf-8") as closure:
        for path in closure.read().splitlines():
            sandbox += ["--ro-bind", path, path]
    for path in ("/etc/passwd", "/etc/group"):
        sandbox += ["--ro-bind", path, path]
    for path in TRANSFER_DIRECTORIES:
        if os.path.isdir(path):
            sandbox += ["--bind", path, path]
    return [*sandbox, "--chdir", TRANSFER_DIRECTORIES[0], "--", *command]


def named(value):
    return re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", value) is not None


def command_argv(args):
    """Reject shell syntax and any Docker options outside the migration protocol."""
    if not args:
        raise ValueError("an explicit migration command is required")
    if args[0] in ("sftp-server", "@openssh@/libexec/sftp-server"):
        if len(args) == 1:
            return ["@openssh@/libexec/sftp-server"]
    elif args[0] in ("scp", "@openssh@/bin/scp"):
        # Only the legacy SCP server modes; no client, program, or SSH options.
        flags = args[1:-1]
        end_options = flags[-1:] == ["--"]
        if end_options:
            flags = flags[:-1]
        if (
            len(args) >= 3
            and all(flag in ("-t", "-f", "-r", "-p", "-d", "-v", "-q") for flag in flags)
            and len(flags) == len(set(flags))
            and sum(flag in flags for flag in ("-t", "-f")) == 1
            and args[-1]
            and (end_options or not args[-1].startswith("-"))
        ):
            path = args[-1]
            if path == "~" or path.startswith("~/"):
                path = "/home/docker" + path[1:]
            return ["@openssh@/bin/scp", *flags, "--", path]
    elif args[0] in ("docker", DOCKER):
        tail = args[1:]
        if len(tail) == 2 and tail[0] in ("stop", "start") and named(tail[1]):
            return [DOCKER, *tail]
        if len(tail) in (2, 3) and tail[0] == "migration-plan" and all(map(named, tail[1:])):
            return [DOCKER, *tail]
        if len(tail) == 3 and tail[:2] in (["volume", "inspect"], ["volume", "create"]) and named(tail[2]):
            return [DOCKER, *tail]
        if tail in (["image", "inspect", "alpine"], ["pull", "alpine"]):
            return [DOCKER, *tail]
        if (
            len(tail) == 5
            and tail[:2] == ["ps", "--filter"]
            and tail[2].startswith("volume=")
            and named(tail[2][7:])
            and tail[3:] == ["--format", "{{.Names}}"]
        ):
            return [DOCKER, *tail]
        if tail[:2] == ["run", "--rm"]:
            rest = tail[2:]
            streaming = rest[:1] == ["-i"]
            if streaming:
                rest = rest[1:]
            if len(rest) < 6 or rest[0] != "-v":
                raise ValueError("unsupported container invocation")
            volume, separator, mount = rest[1].partition(":")
            if not named(volume) or not separator or rest[2:4] != ["alpine", "sh"]:
                raise ValueError("only named volumes and the migration image are permitted")
            shell = rest[4:]
            if len(shell) == 2 and shell[0] == "-c":
                script = shell[1]  # Existing v3 clients; execute with pipefail below.
            elif len(shell) == 5 and shell[:4] == ["-eu", "-o", "pipefail", "-c"]:
                script = shell[4]
            else:
                raise ValueError("unsupported archive command")
            count = "find /volume -type f | wc -l"
            restores = {f"{program} | tar xf - -C /volume" for program in ("cat", "gunzip", "bunzip2")}
            restores.add("apk add --no-cache xz > /dev/null 2>&1 && unxz | tar xf - -C /volume")
            if (streaming and mount == "/volume" and script in restores) or (
                not streaming and mount == "/volume:ro" and script == count
            ):
                return [DOCKER, "run", "--rm", *(["-i"] if streaming else []), "-v", rest[1],
                        "alpine", "sh", "-eu", "-o", "pipefail", "-c", script]
    raise ValueError("only volume migration and SCP/SFTP server commands are permitted")


def migration_plan(volume, selected=None):
    def running(*filters):
        return set(subprocess.check_output(
            [DOCKER, "ps", *filters, "--format", "{{.Names}}"], env=ENV, text=True,
        ).splitlines())

    affected = running("--filter", f"volume={volume}")
    if selected is not None:
        affected.intersection_update([selected])
    # Stopping a required OCI unit also stops its dependents, even when those
    # containers use other volumes. Snapshot their state before stopping any unit.
    while True:
        expanded = affected | {name for name, service in SERVICES.items()
                               if affected.intersection(service["dependsOn"])}
        if expanded == affected:
            break
        affected = expanded
    for name in sorted(affected & running()):
        print(name)


def main():
    try:
        args = sys.argv[1:] or shlex.split(os.environ.get("SSH_ORIGINAL_COMMAND", ""))
        command = command_argv(args)
        if command[0] in ("@openssh@/bin/scp", "@openssh@/libexec/sftp-server"):
            command = transfer_argv(command)
        if command[0] == DOCKER and command[1] == "migration-plan":
            migration_plan(*command[2:])
            return 0
        if command[0] == DOCKER and command[1] in ("stop", "start"):
            action, name = command[1:]
            if name in SERVICES:
                command = ["/run/wrappers/bin/sudo", "-n", SYSTEMCTL, action, SERVICES[name]["unit"]]
            elif action == "stop":
                # Auto-removed unmanaged containers cannot be recovered with docker start.
                result = subprocess.run(
                    [DOCKER, "inspect", "--format", "{{.HostConfig.AutoRemove}}", name],
                    env=ENV, check=True, capture_output=True, text=True,
                )
                if result.stdout.strip() != "false":
                    raise ValueError("auto-remove containers must be managed through a declared systemd unit")
        os.execve(command[0], command, ENV)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Migration command denied or failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
