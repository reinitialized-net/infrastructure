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
│       ├── mesh-status.sh    # Standalone script
│       └── mesh-test.sh      # Script with package substitution
└── containers/
    ├── default.nix           # Main containers module
    ├── containerTools.nix    # Tool loading module
    └── tools/
        └── migrate-volumes.sh # Standalone bash script
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

## Pattern 2: Standalone Scripts (containers)

For pure bash scripts that don't need Nix packages:

### Script File (tools/migrate-volumes.sh)
```bash
#!/bin/bash
# Standard bash script - no placeholders needed
docker volume ls
# ... rest of script
```

### Tool Module (containerTools.nix)
```nix
{
  lib,
  pkgs,
  ...
}: let
  makeToolScript = name: scriptPath:
    pkgs.writeScriptBin name (builtins.readFile scriptPath);
  
  toolsDir = ./tools;
  scriptFiles = builtins.attrNames (builtins.readDir toolsDir);
  
  toolScripts = map (filename:
    let
      scriptName = lib.removeSuffix ".sh" filename;
      scriptPath = "${toolsDir}/${filename}";
    in
      makeToolScript scriptName scriptPath
  ) (builtins.filter (name: lib.hasSuffix ".sh" name) scriptFiles);
in {
  environment.systemPackages = toolScripts;
}
```

**Key Points:**
- No substitution needed - scripts are loaded as-is
- Automatically discovers all `.sh` files in tools directory
- Simple and straightforward for pure bash scripts
- Import this module in the main profile module

## Integration

Both patterns require importing the tool module in the main profile module:

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

## Adding New Scripts

### With Package Substitution (Pattern 1)

1. Create script file in `tools/` directory with `@package-name@` placeholders
2. Add entry to tool module's `toolScripts` list with appropriate substitutions:
   ```nix
   (makeToolScript "my-tool" ./tools/my-tool.sh {
     package-name = "${pkgs.package-name}";
   })
   ```

### Standalone Script (Pattern 2)

1. Create script file in `tools/` directory
2. No changes needed - automatically discovered by `builtins.readDir`

## Benefits

- **Separation of Concerns**: Script logic is separate from Nix configuration
- **Editor Support**: Better syntax highlighting and linting for bash scripts
- **Version Control**: Clearer diffs when scripts change
- **Reusability**: Scripts can be tested independently
- **Maintainability**: Easier to update and refactor scripts
