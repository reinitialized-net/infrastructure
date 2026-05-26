# Examples

These examples match the current repository patterns. They are written for changes inside this repository, where `self` is the flake being edited.

## Add A New Exported VM

1. Create `hosts/apps4.nix`:

```nix
{
  networking = {
    hostName = "apps4";
    useDHCP = false;
  };

  systemd.network.networks.eth0 = {
    address = [ "10.1.11.5/24" ];
    dns = [ "10.1.11.2" "10.1.11.3" ];
    ntp = [ "10.1.11.1" ];
    gateway = [ "10.1.11.1" ];
    matchConfig.Path = "pci-0000:06:12.0";
  };

  services.meshNetwork.enable = true;
}
```

2. Add a secret template in `modules/secrets.example/apps4.nix`:

```nix
{
  lib,
  ...
}: {
  secrets = {
    meshNetwork = {
      description = "MeshNetwork WireGuard private key";
      file = lib.mkDefault (builtins.toFile "mesh-privatekey" "PLACE PRIVATE KEY HERE");
    };
    volumeMigration = {
      description = "SSH private key for docker volume migration between hosts";
      file = lib.mkDefault (builtins.toFile "volume-migration-key" "PLACE PRIVATE KEY HERE");
    };
  };
}
```

3. Add the public key and endpoint to `modules/profiles/meshNetwork/meshTopology.nix`.

4. Add the host to `flake.nix` using `makeDualExport`:

```nix
apps4 = library.makeDualExport "apps4" {
  system = "x86_64-linux";
  vmId = 210;
  enableProtection = true;
  memory = 8192;
  disks = [
    { storage = "hotData"; size = 20; }
    { storage = "coldData"; size = 50; }
  ];
  networking = [
    { bridge = "vmbr0"; firewall = false; vlan = 11; }
  ];
  modules = [
    inputs.vscodeServer.nixosModules.default
    "${inputs.self}/modules/profiles/containers"
    "${inputs.self}/modules/profiles/mountData.nix"
  ];
};
```

5. Export both outputs:

```nix
nixosConfigurations.apps4 = dualSystems.apps4.nixosSystem;

packages = library.forAllSystems (system: {
  apps4 = dualSystems.apps4.package;
});
```

In the current `flake.nix`, the package set is already centralized; add the new attr beside the existing hosts.

6. Validate:

```bash
nix build path:.#nixosConfigurations.apps4.config.system.build.toplevel
```

## Build A Host Without Deploying

```bash
nix build path:.#nixosConfigurations.apps1.config.system.build.toplevel
```

Use this for host-only changes. For shared library or profile changes, build every exported host's toplevel.

## Build A Proxmox VMA

```bash
nix build path:.#packages.x86_64-linux.apps1
```

The result contains:

```text
result/
├── vzdump-qemu-204.vma.zst
└── CREDENTIALS.txt
```

Import on Proxmox:

```bash
qmrestore /var/lib/vz/dump/vzdump-qemu-204.vma.zst 204 --storage hotData
qm start 204
```

## Add A Container Service

Add the container to the relevant host file:

```nix
{
  virtualisation.oci-containers.containers.example = {
    autoStart = true;
    hostname = "example";
    image = "docker.io/library/nginx:latest";
    networks = [ "backend" ];
    ports = [
      "10.255.0.5:1030:80/tcp"
    ];
    volumes = [
      "example_data:/usr/share/nginx/html"
    ];
  };
}
```

Then update:

- [Mesh Network Port Reference](mesh-network-ports.md)
- `rp1` virtual hosts or stream config if the service needs ingress
- `modules/secrets.example/<host>.nix` if the service consumes new secrets

Validate the host:

```bash
nix build path:.#nixosConfigurations.apps3.config.system.build.toplevel
```

## Add Source-Scoped Firewall Rules

Prefer the custom allowlist/denylist options for source-scoped access:

```nix
networking.firewall.allowlist = [
  {
    port = 443;
    protocol = "tcp";
    ipType = "ipv4";
    source = [
      "10.0.0.0/8"
      "192.168.0.0/16"
    ];
  }
];
```

Deny all with specific exceptions:

```nix
networking.firewall = {
  denylist = [
    {
      port = 22;
      protocol = "tcp";
      source = [ "0.0.0.0/0" ];
    }
  ];

  allowlist = [
    {
      port = 22;
      protocol = "tcp";
      source = [ "10.255.0.0/24" ];
    }
  ];
};
```

## Add A `/mnt/data`-Backed User

Use `library/makeUser.nix` directly:

```nix
{
  self,
  pkgs,
  ...
}: {
  imports = [
    "${self}/modules/profiles/mountData.nix"

    (import "${self}/library/makeUser.nix" {
      username = "myservice";
      group = "myservice";
      homeDirectory = "/mnt/data/myservice";
      dataPath = "/mnt/data/myservice";
      extraUserAttrs = {
        isSystemUser = true;
        shell = pkgs.bashInteractive;
      };
    })
  ];
}
```

When `homeDirectory` and `dataPath` are the same, no bind mount is created; the home already lives on `/mnt/data`.

## Use `updateNetworkFirewallRules`

On `devenv`, run a dry run first:

```bash
updateNetworkFirewallRules --dry-run
```

Common overrides:

```bash
OPNSENSE_HOST=10.1.1.1 \
OPNSENSE_API_KEY=key \
OPNSENSE_API_SECRET=secret \
updateNetworkFirewallRules --dry-run --days 14 --top-flows 100
```

The tool can also read `secrets.opnsenseFirewall` from `modules/secrets/devenv.nix`.

## Deploy From `devenv`

Deploy one remote host:

```bash
rebuildHost apps1
```

Deploy a boot-only update:

```bash
rebuildHost rp1 --boot
```

Deploy every topology host:

```bash
updateInfra
```

Do not run remote deploys with `sudo`. The scripts use SSH as `rnetadmin` and pass `--sudo` to the target.

## See Also

- [Library Functions](library-functions.md)
- [Profiles](profiles.md)
- [Modules Overview](modules/README.md)
