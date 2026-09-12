# Secrets Management Module

**Module path:** `modules/profiles/secrets.nix`

**Primary option:** `secrets`

## Overview

The secrets module defines a simple option namespace for passing secret values and secret file paths to other NixOS modules. It does not encrypt, decrypt, create, or permission files by itself.

Live host modules belong in a protected directory outside the checkout, normally
`/var/lib/infratainer/secrets`. Templates under `modules/secrets.example/`
document the keys expected by each host.

## Option Schema

```nix
secrets.<name> = {
  description = "Human-readable purpose";
  keys = {
    # arbitrary Nix values
  };
  file = "/run/secrets/secret-file";
};
```

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `description` | string | `""` | Maintainer-facing description |
| `keys` | attrset of anything | `{}` | Structured values, usually container environment variables |
| `file` | null or path | `null` | Path to a file consumed by another module or service |

## Import Behavior

When `INFRA_SECRETS_DIR` is set, `makeConfiguration` imports
`$INFRA_SECRETS_DIR/<host>.nix` and fails if it is missing. No live in-tree
fallback exists: `path:` flakes copy ignored files into the Nix store.

Using `INFRA_SECRETS_DIR` requires impure flake evaluation. The standard host-local `nixos-upgrade` path sets `--impure` automatically, and the devenv automation passes it for managed-checkout validation and deploys.

The `secrets` option must still be defined by importing `modules/profiles/secrets.nix`; current exported hosts get that through `meshNetwork` or `containers`.

`nixosModules.default` also imports the secrets module for external module consumers.

## Security Notes

Inline values in Nix files can end up readable in the Nix store. This repository uses inline examples because `modules/secrets.example/` is not secret material. For live sensitive values, prefer `file` references that point to files with appropriate runtime permissions, or integrate an external secret manager.

Build from a clean Git checkout with an external secret overlay. `path:.` includes
gitignored files: using it in a checkout containing `modules/secrets/` copies those
files into the store even when the secrets themselves use runtime paths. Do not
copy live secret files into a build snapshot.

Do not create or commit:

- live files under `modules/secrets/`
- generated VMA `result/`
- `result/CREDENTIALS.txt`

## Common Patterns

### WireGuard Mesh Private Key

The mesh module reads only `secrets.meshNetwork.file`:

```nix
{
  lib,
  ...
}: {
  secrets.meshNetwork = {
    description = "MeshNetwork WireGuard private key";
    file = lib.mkDefault "/run/secrets/mesh-privatekey";
  };
}
```

Public keys belong in `modules/profiles/meshNetwork/meshTopology.nix`.

Provision private-key files separately with restrictive ownership and permissions before their services start on every boot. `/run` is volatile: use boot-time secret provisioning or a protected persistent path. Keep the path quoted; embedding private keys with `builtins.toFile` or Nix path literals can copy them into readable Nix artifacts.

### ACME DNS-01 Credentials

Hosts using Technitium DNS-01 set:

```nix
secrets.acmeDns = {
  description = "Technitium DNS API credentials for ACME DNS-01 challenge";
  file = lib.mkDefault "/var/lib/service-secrets/acme-dns.env";
};
```

The NixOS ACME module consumes `config.secrets.acmeDns.file`.

Provision that file separately, owned by root with mode `0600`, containing
`TECHNITIUM_SERVER_BASE_URL` and `TECHNITIUM_API_TOKEN` as environment assignments.
Do not generate it using `builtins.toFile` or `environment.etc.*.text`.

### Container Environment Files

Production containers consume fixed root-owned environment files under
`/var/lib/service-secrets`. Provision every required file before activation;
the Nix configuration deliberately does not synthesize secret-bearing files.

```nix
/var/lib/service-secrets/forgejo-runner.env
```

Provision each file before activation, with the same values used by the service
today. Docker's env-file format uses literal `NAME=value` lines, without shell
quoting, expansion or `export`. Remove any duplicated entries from `keys`, because
explicit environment variables take precedence over env-file values. Nonsecret
settings can remain in `keys`. UniFi uses two files because the images require
different names: `unifi-mongodb.env` contains
`MONGO_INITDB_ROOT_USERNAME/PASSWORD`; `unifi.env` contains
`MONGO_USER/PASS/DBNAME/PORT/AUTHSOURCE`.

This support does not remove credentials from old generations or rotate them.
Migrate and verify each service before coordinating token/password rotation.
Preserve application encryption keys; replacing them blindly can make data
unreadable. Changing `POSTGRES_PASSWORD` alone does not change an existing
PostgreSQL role's password. Runner registration still supplies its credential
through the CLI. The runner no longer receives a Forgejo admin token or Docker
`--privileged`, but its Docker socket remains host-root-equivalent; run only
trusted jobs until it is moved to a disposable isolated host.

### Docker Volume Migration

Container hosts expect:

```nix
secrets.volumeMigration = {
  description = "SSH private key for docker volume migration between hosts";
  file = lib.mkDefault "/run/secrets/volume-migration-key";
};
```

Provision the source file before the key-deployment unit starts. The containers profile copies it to `/var/lib/docker-volume-migration/identity` inside a root-owned directory, with mode `0600` and ownership `docker:docker`.

### OPNsense Firewall Tool

`updateNetworkFirewallRules` on `devenv` reads:

```nix
/var/lib/service-secrets/opnsense.env
```

The root-owned mode-0640 file is read at runtime and uses the variables below.
Process environment variables override the file, and CLI flags override both:

| Environment variable | Meaning |
|----------------------|---------|
| `OPNSENSE_HOST` | Firewall host or IP |
| `OPNSENSE_API_KEY` | API key |
| `OPNSENSE_API_SECRET` | API secret |
| `OPNSENSE_PORT` | Management port |
| `OPNSENSE_VERIFY_TLS` | `true` to verify TLS certificates |
| `LOG_DAYS` | Log range label used by the tool; OPNsense API retention still controls available logs |
| `TOP_FLOWS` | Number of top flows to analyze |

## Host Secret Templates

| Template | Important secrets consumed by source |
|----------|--------------------------------------|
| `modules/secrets.example/devenv.nix` | `meshNetwork`, `opnsenseFirewall`, `volumeMigration` |
| `modules/secrets.example/rp1.nix` | `meshNetwork`, `acmeDns`, `volumeMigration` |
| `modules/secrets.example/apps1.nix` | `meshNetwork`, `acmeDns`, `hudu`, `jaeger`, `grafana`, `stalwart`, `forgejo`, `authentik`, `volumeMigration` |
| `modules/secrets.example/apps2.nix` | `meshNetwork`, `acmeDns`, `unifi`, `pgAdmin4`, `redisInsight`, `forgejoRunner`, `volumeMigration` |
| `modules/secrets.example/apps3.nix` | `meshNetwork`, `immich`, `tuwunel`, `paperless`, `pelican`, `ocis`, `volumeMigration` |
| `modules/secrets.example/db1.nix` | `meshNetwork`, `postgres1`, `volumeMigration` |
| `modules/secrets.example/gs1.nix` | `meshNetwork`, `volumeMigration`, `wings` |

When adding or renaming a secret consumed by `hosts/<host>.nix` or a profile, update the matching example file.

## External Secret Managers

The module can reference paths produced by tools such as sops-nix or agenix:

```nix
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  sops.secrets.mesh-private-key.sopsFile = ./secrets/mesh.yaml;

  secrets.meshNetwork = {
    description = "Mesh private key from sops-nix";
    file = config.sops.secrets.mesh-private-key.path;
  };
}
```

The important contract is that the consuming module receives a path in `secrets.<name>.file` or values in `secrets.<name>.keys`.

## See Also

- [Mesh Network Module](meshNetwork.md)
- [Containers Profile](containers.md)
- [Examples](../examples.md)
