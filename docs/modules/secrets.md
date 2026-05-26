# Secrets Management Module

**Module path:** `modules/profiles/secrets.nix`

**Primary option:** `secrets`

## Overview

The secrets module defines a simple option namespace for passing secret values and secret file paths to other NixOS modules. It does not encrypt, decrypt, create, or permission files by itself.

Live files under `modules/secrets/` are ignored by git. Templates under `modules/secrets.example/` document the keys expected by each host.

## Option Schema

```nix
secrets.<name> = {
  description = "Human-readable purpose";
  keys = {
    # arbitrary Nix values
  };
  file = /path/to/secret-file;
};
```

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `description` | string | `""` | Maintainer-facing description |
| `keys` | attrset of anything | `{}` | Structured values, usually container environment variables |
| `file` | null or path | `null` | Path to a file consumed by another module or service |

## Import Behavior

`makeConfiguration` automatically imports `modules/secrets/<host>.nix` when the file exists. The `secrets` option must still be defined by importing `modules/profiles/secrets.nix`; current exported hosts get that through `meshNetwork` or `containers`.

`nixosModules.default` also imports the secrets module for external module consumers.

## Security Notes

Inline values in Nix files can end up readable in the Nix store. This repository uses inline examples because `modules/secrets.example/` is not secret material. For live sensitive values, prefer `file` references that point to files with appropriate runtime permissions, or integrate an external secret manager.

Do not commit:

- `modules/secrets/`
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
    file = lib.mkDefault (builtins.toFile "mesh-privatekey" "PLACE PRIVATE KEY HERE");
  };
}
```

Public keys belong in `modules/profiles/meshNetwork/meshTopology.nix`.

### ACME DNS-01 Credentials

Hosts using Technitium DNS-01 set:

```nix
secrets.acmeDns = {
  description = "Technitium DNS API credentials for ACME DNS-01 challenge";
  file = lib.mkDefault (builtins.toFile "acme-dns-credentials" ''
    TECHNITIUM_SERVER_BASE_URL=http://10.255.0.3:1026/
    TECHNITIUM_API_TOKEN=PLACE_API_TOKEN_HERE
  '');
  keys = {
    apiToken = "PLACE_API_TOKEN_HERE";
  };
};
```

The NixOS ACME module consumes `config.secrets.acmeDns.file`.

### Docker Volume Migration

Container hosts expect:

```nix
secrets.volumeMigration = {
  description = "SSH private key for docker volume migration between hosts";
  file = lib.mkDefault (builtins.toFile "volume-migration-key" "PLACE PRIVATE KEY HERE");
};
```

The containers profile writes this key to `/home/docker/.ssh/volume-migration-key`.

### OPNsense Firewall Tool

`updateNetworkFirewallRules` on `devenv` reads `secrets.opnsenseFirewall`:

```nix
secrets.opnsenseFirewall = {
  description = "OPNsense firewall API credentials";
  file = lib.mkDefault /run/secrets/opnsense-api-secret;
  keys = {
    host = "OPNSENSE_HOST_OR_IP";
    port = "443";
    apiKey = "PLACE_API_KEY_HERE";
    apiSecret = "PLACE_API_SECRET_HERE";
  };
};
```

Environment variables override secrets, and CLI flags override both:

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
| `modules/secrets.example/ai1.nix` | `meshNetwork`, `openclaw` |
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
