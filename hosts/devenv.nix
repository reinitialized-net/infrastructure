{
  self,
  pkgs,
  lib,
  ...
}:{
  imports = [
    ((import "${self}/library/makeUser.nix" {}) {
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
        #"10.1.11.3"
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
      nodeId = 1;
    };
  };
  # Install development tools
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    btop
    fastfetch

    nmap
    dig
    coreutils
    pciutils
    usbutils

    nixd
    nixfmt-rfc-style
  ];
}