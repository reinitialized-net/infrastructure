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
in
{
  imports = [
    # DevEnv-exclusive fleet management & infrastructure tools
    ./devenv/devenvTools.nix

    (import "${self}/library/makeUser.nix" {
      username = "develop";
      group = "develop";
      homePermissions = "0700";
      extraUserAttrs = {
        extraGroups = [ "docker" "wheel" ];
        shell = pkgs.bashInteractive;
        isNormalUser = true;

        initialPassword = "!";
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
    nixfmt-rfc-style

    # GPG tools - pinentry must be in PATH for GPG agent
    pinentry-curses

    pkgsUnstable.opencode
    pkgsUnstable.codex
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
