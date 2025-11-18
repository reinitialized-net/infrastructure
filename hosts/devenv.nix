# hosts/devenv.nix
## Defines configuration for the development environment VS.
{ defaultStateVersion, lib, pkgs, pkgsUnstable, ...}:  
{
  networking = {
    hostName = "devenv";
    # Disable DHCP for static configuration (WILL OVERRIDE IF ENABLED)
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
      gateway = [ 
        "10.1.200.1"
      ];
      matchConfig = {
        Path = "pci-0000:06:12.0";
      };
    };
  };
  # Enable support for VS Code Remote - SSH
  services.vscode-server.enable = true;
  # Install desired packages
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    btop
    fastfetch
    docker-compose

    nmap
    dig
    coreutils
    pciutils
    usbutils

    nixd
    nixfmt-rfc-style
  ];
  # Create develop user
  fileSystems."/home/develop" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi2";
    fsType = "ext4";
    options = [ "defaults" ];

    autoResize = true;
    autoFormat = true;
  };
  users.users.develop = {
    extraGroups = [ "docker" "wheel" ];
    shell = pkgs.bashInteractive;

    isNormalUser = true;
    home = "/home/develop";
    initialPassword = "!";

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEgNNIkOFenuf9S6sy5heFeysErwMgfGD//r4jWgbg/E develop"
    ];
  };
}