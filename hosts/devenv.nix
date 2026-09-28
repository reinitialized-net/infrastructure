{
  self,
  nixpkgsUnstable,
  pkgs,
  system,
  ...
}:
let
  pkgsUnstable = import nixpkgsUnstable {
    inherit system;
    config = pkgs.config;
  };

  # Stdio GitHub MCP server shared by Claude Code and Codex. The PAT stays in a
  # user-owned file outside the flake and out of both clients' config files.
  githubMcp = pkgs.writeShellApplication {
    name = "github-mcp";
    runtimeInputs = [ pkgsUnstable.github-mcp-server ];
    text = ''
      token_file="''${GITHUB_MCP_TOKEN_FILE:-''${XDG_CONFIG_HOME:-$HOME/.config}/github-mcp/token}"
      if [ ! -r "$token_file" ]; then
        echo "github-mcp: token file not readable: $token_file" >&2
        exit 1
      fi
      GITHUB_PERSONAL_ACCESS_TOKEN="$(head -n 1 "$token_file" | tr -d '\r\n')"
      if [ -z "$GITHUB_PERSONAL_ACCESS_TOKEN" ]; then
        echo "github-mcp: token file is empty: $token_file" >&2
        exit 1
      fi
      export GITHUB_PERSONAL_ACCESS_TOKEN
      exec github-mcp-server stdio "$@"
    '';
  };

  # Roblox Studio's built-in MCP is a stdio bridge that must run beside Studio,
  # so run it over SSH on the Windows workstation. Host, user, and key come from
  # the `roblox-studio` alias in ~/.ssh/config (override: ROBLOX_STUDIO_SSH_HOST).
  robloxStudioMcp = pkgs.writeShellApplication {
    name = "roblox-studio-mcp";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      exec ssh -T -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30 \
        "''${ROBLOX_STUDIO_SSH_HOST:-roblox-studio}" \
        'cmd.exe /c "%LOCALAPPDATA%\Roblox\mcp.bat"'
    '';
  };
in
{
  imports = [
    # DevEnv-exclusive fleet management & infrastructure tools
    ./devenv/devenvTools.nix
    ./devenv/infraAutoUpdate.nix

    (import "${self}/library/makeUser.nix" {
      username = "develop";
      group = "develop";
      homePermissions = "0700";
      extraUserAttrs = {
        extraGroups = [
          "docker"
          "wheel"
        ];
        shell = pkgs.bashInteractive;
        isNormalUser = true;

        # Lock password authentication while retaining SSH public-key access.
        hashedPassword = "!";
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEgNNIkOFenuf9S6sy5heFeysErwMgfGD//r4jWgbg/E develop"
        ];
      };
    })
  ];
  # Networking Configuration
  networking = {
    hostName = "devenv";
    useDHCP = false;
  };
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.200.2/24"
      ];
      dns = [
        "10.1.11.2"
        "10.1.11.3"
      ];
      ntp = [
        "10.1.200.1"
      ];
      gateway = [
        "10.1.200.1"
      ];
      matchConfig.Path = "pci-0000:06:12.0";
    };
  };
  # Configure Services
  services = {
    vscode-server.enable = true;
    meshNetwork = {
      enable = true;
    };
  };
  # Install development tools
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    btop
    fastfetch

    wget

    nmap
    dig
    coreutils
    pciutils
    usbutils

    nixd
    nixfmt

    # GPG tools - pinentry must be in PATH for GPG agent
    pinentry-curses

    pkgsUnstable.codex
    githubMcp
    robloxStudioMcp
    pkgsUnstable.gh
    pkgsUnstable.nodejs_22
    pkgsUnstable.python3
  ];
  # Enable required programs
  programs = {
    nix-ld.enable = true;
    gnupg.agent = {
      enable = true;
      # Pick a flavor (e.g., "curses" for terminal, "gnome3" or "qt" for GUI)
      pinentryPackage = pkgs.pinentry-curses;
    };
  };
  # Nix Settings
  nix.settings = {
    # Increase download buffer size to prevent warnings during large downloads
    # Default is 64 MiB (67108864), setting to 256 MiB (268435456)
    download-buffer-size = 268435456;
  };
}
