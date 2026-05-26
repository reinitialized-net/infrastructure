# Bash Script Tools Organization

This document describes how bash script tools are organized and integrated into NixOS modules.

## Overview

Bash scripts are stored as separate `.sh` files in `modules/profiles/*/tools/` directories and loaded by dedicated tool modules (`*Tools.nix`). This improves:
- **Readability**: Scripts are easier to edit in separate files
- **Maintainability**: Changes to scripts don't require editing Nix module code
- **Organization**: Clear separation between script logic and module configuration

## Directory Structure

```
modules/profiles/
├── meshNetwork/
│   ├── default.nix          # Main mesh network module
│   ├── meshTools.nix         # Tool loading module
│   └── tools/
│       ├── mesh-keygen.sh    # Script with package substitution
│       ├── mesh-status.sh    # Script with package substitution
│       └── mesh-test.sh      # Script with package substitution
└── containers/
    ├── default.nix           # Main containers module
    ├── containerTools.nix    # Tool loading module
    └── tools/
        └── migrate-volumes.sh # Script with package substitution

hosts/devenv/
├── devenvTools.nix          # Fleet management tool loader
└── tools/
    ├── rebuild-host.sh       # Script with dynamic substitution
    ├── update-infra.sh       # Script with dynamic substitution
    └── update-network-firewall-rules.sh  # Script with package substitution
```

## Pattern 1: Scripts with Package Substitution (meshNetwork)

For scripts that need to reference Nix packages (e.g., `wireguard-tools`, `iputils`):

### Script File (tools/mesh-keygen.sh)
```bash
#!/usr/bin/env bash
# Use @package-name@ placeholders for Nix packages
PRIVATE_KEY=$(@wireguard-tools@/bin/wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | @wireguard-tools@/bin/wg pubkey)
```

### Tool Module (meshTools.nix)
```nix
{
  lib,
  pkgs,
  config,
  ...
}: let
  meshEnabled = config.services.meshNetwork.enable or false;
  
  # Helper function to create a script with package substitution
  makeToolScript = name: scriptPath: substitutions:
    let
      scriptContent = builtins.readFile scriptPath;
      # Replace @package@ style placeholders with actual paths
      replacedContent = lib.replaceStrings
        (map (key: "@${key}@") (builtins.attrNames substitutions))
        (builtins.attrValues substitutions)
        scriptContent;
    in
      pkgs.writeScriptBin name replacedContent;
  
  toolScripts = with pkgs; [
    (makeToolScript "mesh-keygen" ./tools/mesh-keygen.sh {
      wireguard-tools = "${wireguard-tools}";
    })
  ];
in {
  environment.systemPackages = lib.mkIf meshEnabled toolScripts;
}
```

**Key Points:**
- Use `@package-name@` placeholders in the shell script
- The tool module uses `lib.replaceStrings` to substitute package paths
- Conditionally install tools based on feature enablement
- Import this module in the main profile module

## Pattern 2: Scripts with Package Substitution (containers)

Container tools also use package substitution, with explicitly listed scripts and their dependencies:

### Script File (tools/migrate-volumes.sh)
```bash
#!/usr/bin/env bash
# Uses @package@ placeholders for Nix packages
@docker@/bin/docker volume ls
# ... rest of script
```

### Tool Module (containerTools.nix)
```nix
{
  lib,
  pkgs,
  ...
}: let
  # Helper function to create a script with package substitution
  makeToolScript = name: scriptPath: substitutions:
    let
      scriptContent = builtins.readFile scriptPath;
      replacedContent = lib.replaceStrings
        (map (key: "@${key}@") (builtins.attrNames substitutions))
        (builtins.attrValues substitutions)
        scriptContent;
    in
      pkgs.writeScriptBin name replacedContent;
  
  toolScripts = with pkgs; [
    (makeToolScript "migrate-volumes" ./tools/migrate-volumes.sh {
      docker = "${docker}";
      coreutils = "${coreutils}";
      gawk = "${gawk}";
      openssh = "${openssh}";
      gnugrep = "${gnugrep}";
    })
  ];
in {
  environment.systemPackages = toolScripts;
}
```

**Key Points:**
- Uses the same `makeToolScript` pattern as meshNetwork tools
- Explicitly lists each script with its required package substitutions
- Scripts use `@package@` placeholders resolved to Nix store paths
- Import this module in the main profile module

## Integration

All patterns require importing the tool module in the parent module:

```nix
# modules/profiles/meshNetwork/default.nix
{
  imports = [ 
    "${self}/modules/profiles/meshNetwork/meshTools.nix"
  ];
  
  # ... rest of module
}
```

```nix
# modules/profiles/containers/default.nix
{
  imports = [ 
    ./containerTools.nix
  ];
  
  # ... rest of module
}
```

```nix
# hosts/devenv.nix
{
  imports = [
    ./devenv/devenvTools.nix
  ];
  
  # ... rest of host config
}
```

## Pattern 3: Dynamic Substitution from Nix Data (devenvTools)

For scripts that need computed data from Nix expressions (e.g., mesh topology data):

### Script File (tools/rebuild-host.sh)
```bash
#!/usr/bin/env bash
# Uses @placeholder@ for Nix-computed values
VALID_HOSTS="@validHosts@"

get_host_ip() {
  local host="$1"
  case "$host" in
@hostIpCases@
    *) echo "ERROR: Unknown host" >&2; return 1 ;;
  esac
}
```

### Tool Module (devenvTools.nix)
```nix
{
  self,
  lib,
  pkgs,
  config,
  ...
}: let
  meshTopology = import "${self}/modules/profiles/meshNetwork/meshTopology.nix" { inherit lib; };
  validHosts = builtins.attrNames meshTopology.nodes;
  validHostsStr = lib.concatStringsSep " " validHosts;

  hostIpCases = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: ip:
      "      ${name}) echo \"${ip}\" ;;"
    ) hostIpMap
  );

  makeToolScript = name: scriptPath: substitutions: /* ... */;

  toolScripts = with pkgs; [
    (makeToolScript "rebuildHost" ./tools/rebuild-host.sh {
      validHosts = validHostsStr;
      hostIpCases = hostIpCases;
    })
  ];
in {
  environment.systemPackages = toolScripts;
}
```

**Key Points:**
- Substitution values are computed from Nix data (mesh topology, secrets module)
- Host IPs and valid hostnames are automatically derived from `meshTopology.nix`
- Changes to mesh topology automatically update the scripts on rebuild
- Available only on the `devenv` host

## Adding New Scripts

### With Package Substitution (Pattern 1 or 2)

1. Create script file in `tools/` directory with `@package-name@` placeholders
2. Add entry to tool module's `toolScripts` list with appropriate substitutions:
   ```nix
   (makeToolScript "my-tool" ./tools/my-tool.sh {
     package-name = "${pkgs.package-name}";
   })
   ```

### With Dynamic Nix Data (Pattern 3)

1. Create script file in `tools/` directory with `@placeholder@` for computed values
2. Compute substitution values from Nix expressions in the tool module
3. Add entry to tool module's `toolScripts` list:
   ```nix
   (makeToolScript "my-tool" ./tools/my-tool.sh {
     computedValue = myNixExpression;
   })
   ```

## Benefits

- **Separation of Concerns**: Script logic is separate from Nix configuration
- **Editor Support**: Better syntax highlighting and linting for bash scripts
- **Version Control**: Clearer diffs when scripts change
- **Reusability**: Scripts can be tested independently
- **Maintainability**: Easier to update and refactor scripts
