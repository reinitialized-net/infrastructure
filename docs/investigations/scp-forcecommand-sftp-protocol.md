# SCP Fails with ForceCommand: "Received message too long"

## Symptom

When using `migrate-volumes transfer` to send a Docker volume backup to a remote host via the `docker` user, SCP fails with:

```
scp: Received message too long 1097032549
scp: Ensure the remote shell produces no output for non-interactive sessions.
```

The number `1097032549` in hex is `0x41636365`, which decodes to ASCII `"Acce"` — the start of the deny message `"Access denied: only volume migration commands are permitted"`.

## Root Cause

**Two issues combined:**

### 1. Modern SCP uses SFTP protocol internally

OpenSSH 9.0+ changed `scp` to use the SFTP protocol by default instead of the legacy SCP/RCP protocol. When `scp` connects to a remote host, it no longer sends `scp -t /path` as the remote command. Instead, it sends:

```
/nix/store/<hash>-openssh-<version>/libexec/sftp-server
```

The ForceCommand validator's `case` statement only matched `scp*` patterns, so the `sftp-server` invocation fell through to the `*)` deny branch.

### 2. Deny message sent to stdout

The deny branch used `echo` (stdout) for the error message:

```sh
echo "Access denied: only volume migration commands are permitted"
```

SCP/SFTP uses stdout for binary protocol communication. The text error message on stdout was interpreted as protocol data, producing the "message too long" error. The `1097032549` byte value is literally the ASCII text of the deny message being parsed as a 4-byte big-endian length field.

## Steps to Identify

1. **Observed** that `sudo -u docker ssh docker@remote "echo hello"` was correctly denied, confirming ForceCommand worked for command filtering.
2. **Observed** that `sudo -u docker ssh docker@remote "scp --help"` succeeded, confirming `scp*` patterns matched.
3. **Decoded** the error number `1097032549` → `0x41636365` → `"Acce"` — matching the start of the deny message, indicating the deny branch was triggered during SCP.
4. **Created a debug validator** on the remote host that logged `$SSH_ORIGINAL_COMMAND` before processing:
   ```
   SSH_ORIGINAL_COMMAND=[/nix/store/...-openssh-10.2p1/libexec/sftp-server]
   DENIED
   ```
5. This confirmed the actual command sent was `sftp-server`, not `scp -t ...`.

## Fix

Two changes to the `dockerSshValidator` script in `modules/profiles/containers/default.nix`:

1. **Added `sftp-server` patterns** to the allowed commands:
   ```sh
   */bin/docker*|docker*|scp*|*/sftp-server*|sftp-server*
   ```

2. **Redirected deny message to stderr** to prevent protocol corruption if future unmatched commands are attempted:
   ```sh
   echo "Access denied: only volume migration commands are permitted" >&2
   ```

## Follow-up: Eliminated SCP from Transfer Mode (v3.0.0)

The SCP approach also had a secondary issue: writing to `/tmp` directories caused permission conflicts when different users had previously created the target directory. Rather than adding more workarounds, the transfer mode was redesigned in v3.0.0 to eliminate intermediate files entirely:

- **Transfer mode** now streams `tar` data directly over SSH into a `docker run` container on the remote, writing straight into the destination Docker volume. No temp files on either host.
- **Export/import modes** now use `/var/lib/docker/volumes/.migration-staging/` instead of `/tmp/volume-migrations/`, keeping backups inside Docker's data directory where bind-mount permissions are correct.
- **ForceCommand** was tightened to only allow `docker*` and `scp/sftp-server*` patterns (removed `mkdir`, `rm`, `chmod`, `cat`, `sha256sum` since temp-file commands are no longer needed).
- **sudo-rs rules** removed the `scp` command allowance (only `ssh` is needed now).

## Key Lesson

When restricting SSH commands via `ForceCommand`, always check what the _actual_ remote command is for each tool. Modern OpenSSH `scp` transparently uses `sftp-server` on the remote side, which is a different binary path than `scp`. Additionally, any `ForceCommand` wrapper must never write to stdout, as SSH subsystems (SCP, SFTP) use stdout for their binary protocol.
