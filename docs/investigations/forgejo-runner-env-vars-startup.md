# Forgejo Runner: Environment Variables Not Supported — Container Exits Immediately

## Symptoms

The `forgejoRunner` container on apps2 would start and immediately exit, printing only the help text:

```
Run Forgejo Actions locally by specifying the event name (e.g. `push`) or an action name directly.

Usage:
  forgejo-runner [command]

Available Commands:
  daemon             Run as a runner daemon
  register           Register a runner to the server
  ...
```

No jobs were being picked up or executed.

## Root Cause

The Forgejo Runner Docker image (`code.forgejo.org/forgejo/runner:12`) is a **bare binary image** — it contains only the `forgejo-runner` Go binary with no entrypoint script. **It does not support configuration via environment variables.**

The container was configured to pass environment variables like `FORGEJO_RUNNER_NAME`, `FORGEJO_RUNNER_LABELS`, `FORGEJO_RUNNER_REGISTRATION_TOKEN`, `FORGEJO_INSTANCE_URL`, etc. None of these are recognized by the runner binary. They are silently ignored.

Three things were missing:

1. **No subcommand**: The default CMD is just `/bin/forgejo-runner` with no arguments, which prints help and exits. The runner requires the `daemon` subcommand to actually run.

2. **No registration**: Before the runner can operate as a daemon, it must be registered with a Forgejo instance. Registration creates a `.runner` file containing the runner's UUID, auth token, instance URL, and labels. Without this file, the daemon refuses to start.

3. **No configuration file**: The runner uses a `config.yml` file for settings like capacity, fetch intervals, labels, and container options. Without it, defaults are used (which may be acceptable, but explicit configuration is preferred).

## Investigation Steps

1. Checked Docker logs on apps2: `sudo docker logs forgejoRunner` — showed only the help text output, confirming the binary was invoked without a subcommand.

2. Inspected the container config: `docker inspect forgejoRunner` — confirmed:
   - `Cmd: [/bin/forgejo-runner]` (no subcommand)
   - Environment variables were set but not consumed by anything
   - No entrypoint script exists in the image

3. Checked the data volume: `ls -la /data/` — empty directory, confirming no `.runner` registration file or `config.yml` existed.

4. Reviewed Forgejo Runner official documentation at `https://forgejo.org/docs/latest/admin/actions/runner-installation/` — confirmed the runner binary does not read environment variables. Configuration is done through:
   - `forgejo-runner register` (creates `.runner` file)
   - `config.yml` (created via `forgejo-runner generate-config`)
   - `forgejo-runner daemon --config config.yml` (starts the daemon)

5. Verified available CLI commands:
   - `forgejo-runner register --no-interactive` supports `--instance`, `--token`, `--name`, `--labels` flags
   - `forgejo-runner create-runner-file` supports offline registration with `--secret`

## Fix Applied

Updated the container definition in `hosts/apps2.nix` to:

1. **Remove environment variables** that the runner doesn't understand (including `DOCKER_HOST`)
2. **Add a `cmd`** with a bash script that:
   - Generates `config.yml` on first run and patches settings (capacity, fetch timeouts)
   - **Patches `container.docker_host` to `"automount"`** — this is the key setting that allows the runner to automatically find the Docker socket and mount it into job containers
   - Registers the runner non-interactively if `.runner` file doesn't exist
   - Starts `forgejo-runner daemon --config /data/config.yml`
3. **Set `workdir = "/data"`** to ensure all runner files are created in the persistent volume

The secrets in `modules/secrets/apps2.nix` are still used, but now interpolated directly into the `cmd` script at Nix evaluation time rather than being passed as container environment variables.

### Docker Socket Access Fix

**Additional Issue Discovered:** After implementing the initial fix, the runner encountered a "permission denied" error when trying to access the Docker socket:

```
Error: cannot ping the docker daemon. permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock
```

**Root Cause Analysis:**

The Docker socket on the host has these permissions:
```
srw-rw---- 1 root docker 0 /var/run/docker.sock
```

This means only `root` and members of the `docker` group (GID 999 on NixOS) can access it.

The Forgejo Runner container runs as user `1000:1000` (non-root), and by default is not a member of the docker group. Even though the socket is mounted into the container, the container process cannot read/write to it.

**Solution Attempts:**

1. **First attempt:** Added `DOCKER_HOST` environment variable → Still failed (doesn't grant permissions)
2. **Second attempt:** Used `--group-add=docker` → Failed with "Unable to find group docker: no matching entries in group file" because the group name doesn't exist inside the container's `/etc/group`
3. **Final solution:** Used `--group-add=999` (numeric GID) → **Success!**

**The Fix:**

Added to `extraOptions` in the container definition:
```nix
extraOptions = [
  "--privileged"
  "--group-add=999"  # Add docker group (GID 999) for socket access
];
```

This adds GID 999 to the container's supplementary groups, allowing the runner process to access the Docker socket.

Also configured `container.docker_host: "automount"` in `config.yml`:
- Makes Forgejo Runner automatically find the Docker socket
- Automatically mounts the socket into job/service/step containers as `/var/run/docker.sock`
- Allows workflow steps like `docker build` and `docker run` to work inside job containers

**Verification:**

After the fix:
```bash
$ docker exec forgejoRunner id
uid=1000 gid=1000 groups=999(ping),1000

$ docker logs forgejoRunner
time="2026-02-08T22:32:19Z" level=info msg="Starting runner daemon"
time="2026-02-08T22:32:19Z" level=info msg="runner: runner-apps2, with version: v12.6.4, with labels: [docker ubuntu-latest], declared successfully"
time="2026-02-08T22:32:19Z" level=info msg="[poller] launched"
```

The runner is now successfully connected and polling for jobs.

## Key Forgejo Runner Facts

| Aspect | Detail |
|--------|--------|
| **Image** | `code.forgejo.org/forgejo/runner:12` |
| **Config method** | `config.yml` file (NOT environment variables) |
| **Registration** | `forgejo-runner register --no-interactive` → creates `.runner` file |
| **Startup** | `forgejo-runner daemon --config config.yml` |
| **Docker access** | Mount `/var/run/docker.sock` + set `container.docker_host: "automount"` in config.yml |
| **Env vars** | Runner binary ignores env vars (except when used by init scripts) |
| **Data directory** | `/data` (contains `.runner`, `config.yml`, `.cache/`) |

### Critical Configuration for Docker Access

The `container.docker_host` setting in `config.yml` controls how the runner accesses Docker:

| Setting | Behavior |
|---------|----------|
| `"-"` (default) | No Docker socket sharing — jobs cannot use Docker |
| `"automount"` | Auto-discovers socket and mounts it into job containers — **recommended** |
| `"unix:///path"` | Explicit socket path to mount |
| `"tcp://host:port"` | TCP connection (cannot be auto-mounted into containers) |

For most use cases, `"automount"` is the correct choice when the runner container has the host's Docker socket mounted.

### Best Practice: Container Group Membership for Socket Access

When mounting the Docker socket into a container, the container process must have permission to access it. On NixOS (and most Linux systems), the socket has these permissions:

```
srw-rw---- 1 root docker 0 /var/run/docker.sock
```

**The solution:** Add the host's docker group to the container using `--group-add=<GID>`:

```nix
extraOptions = [
  "--group-add=999"  # Docker group GID on NixOS
];
```

**Important:** Use the **numeric GID**, not the group name. The group name likely doesn't exist in the container's `/etc/group`, which will cause Docker to fail with "Unable to find group docker: no matching entries in group file".

You can find the docker group GID on the host with:
```bash
getent group docker  # Output: docker:x:999:
```
