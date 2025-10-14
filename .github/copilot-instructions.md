# Copilot Instructions for Reinitialized Infrastructure

## Overview
This repository defines the infrastructure for Reinitialized.net using Nix. The project is structured around Nix Flakes and modular configurations for hardware, profiles, and system services. The primary goal is to maintain declarative, reproducible infrastructure.

### Key Components
- **`flake.nix`**: Entry point for the Nix Flake. Defines inputs and outputs for the project.
- **`hardware/`**: Contains hardware-specific configurations, such as `qemu.nix` for virtualized environments.
- **`profiles/`**: Defines reusable profiles for containers and virtual servers, e.g., `standard.nix`.
- **`.vscode/`**: VS Code workspace settings, including recommended extensions for Nix development.

## Developer Workflows

### Building and Testing Configurations
1. **Build a Nix configuration**:
   ```bash
   nix build .
   ```
2. **Test a configuration in a virtual machine**:
   ```bash
   nix run .#vm
   ```

### Debugging
- Use `nix repl` to interactively debug expressions:
  ```bash
  nix repl
  ```
- Load the flake:
  ```nix
  :lf .
  ```

### Formatting
- Ensure Nix files are formatted using `nixpkgs-fmt`:
  ```bash
  nixpkgs-fmt .
  ```

## Project-Specific Conventions

### Nix Modules
- Use `lib.mkDefault` to set default values for options.
- Follow the structure in `profiles/standard.nix` for defining reusable modules:
  - Configure time, networking, services, packages, users, and security settings.
  - Use `systemd.services` for custom service definitions.

### Security
- Root login is disabled (`PermitRootLogin = "prohibit-password"`).
- Password authentication is disabled (`PasswordAuthentication = false`).
- Use `sudo-rs` instead of traditional `sudo`.

### Automatic Updates
- Automatic security upgrades are enabled via `system.autoUpgrade`.

## Recommended Tools
- **VS Code Extensions**:
  - `github.copilot`
  - `jnoortheen.nix-ide`
  - `arrterian.nix-env-selector`
- **Nix Utilities**:
  - `nixpkgs-fmt` for formatting
  - `nix repl` for debugging

## External Dependencies
- The project fetches `nixpkgs` from the NixOS GitHub repository (`nixos-25.05`).
- Ensure internet connectivity for fetching inputs.

## Examples

### Adding a New Profile
1. Create a new file in `profiles/` (e.g., `profiles/example.nix`).
2. Follow the structure in `profiles/standard.nix`.
3. Import the profile in `flake.nix` or another module as needed.

### Modifying Hardware Configurations
1. Update the relevant file in `hardware/` (e.g., `hardware/qemu.nix`).
2. Test changes using:
   ```bash
   nix build .
   ```

---

For further questions or clarifications, refer to the NixOS documentation or consult the team.