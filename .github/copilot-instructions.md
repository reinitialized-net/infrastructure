# Copilot Instructions for Reinitialized Infrastructure

## Overview
This repository defines the infrastructure for Reinitialized.net using Nix. The project is structured around Nix Flakes and modular configurations for hardware, profiles, and system services. The primary goal is to maintain declarative, reproducible infrastructure.

### Key Components
- **`flake.nix`**: Entry point for the Nix Flake. Defines inputs and outputs for the project.
- **`hardware/`**: Contains hardware-specific configurations, such as `qemu.nix` for virtualized environments.
- **`modules/`**: Defines reusable modules for containers and virtual servers, e.g., `standard.nix`, `docker.nix`.
- **`hosts/`**: Contains host-specific configurations, e.g., `apps1.nix`, `devenv.nix`.
- **`secrets/`**: Contains secret configuration files, e.g., `hudu.nix`.
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
- Follow the structure in `modules/standard.nix` for defining reusable modules:
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

### Adding a New Module
1. Create a new file in `modules/` (e.g., `modules/example.nix`).
2. Follow the structure in `modules/standard.nix`.
3. Import the module in `flake.nix` or another configuration as needed.

### Modifying Hardware Configurations
1. Update the relevant file in `hardware/` (e.g., `hardware/qemu.nix`).
2. Test changes using:
   ```bash
   nix build .
   ```

---

REMEMBER:
- You are an agent - please keep going until the user’s query is completely resolved, before ending your turn and yielding back to the user. Only terminate your turn when you are sure that the problem is solved.
- If you are not sure about file content or codebase structure pertaining to the user’s request, use your tools to read files and gather the relevant information: do NOT guess or make up an answer.
- You MUST plan extensively before each function call, and reflect extensively on the outcomes of the previous function calls. DO NOT do this entire process by making function calls only, as this can impair your ability to solve the problem and think insightfully.
- Before answering any question, always say 'I have read the copilot instructions and will follow them.'