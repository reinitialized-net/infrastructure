# hosts/devenv.nix
## Defines configuration for the development environment VS.
{ pkgs, ...}:
{
  imports = [
    ../modules/standard.nix
    ../modules/docker.nix
    ../hardware/qemu.nix
  ];

  # System-specific configuration
  networking = {
    hostName = "devenv";
    useDHCP = false;
  };
  systemd.network.networks = {
    "10-eth0" = {
      matchConfig = {
        Name = "eth0";
      };
      address = [
        "10.1.200.2/24"
      ];
      routes = [
        {
          Gateway = "10.1.200.1";
        }
      ];
      dns = [ 
        "1.1.1.1" 
        "8.8.8.8" 
      ];
    };
  };

  ## Web-based IDE
  # services.openvscode-server = {
  #   enable = true;
  #   extraArguments = {
  #     "openvscode-server.port" = 8080;
  #   };
  # };
  ## Temporarily use remote-ssh VS Code server until we can switch to openvscode-server
  services.vscode-server.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    btop
    fastfetch
    docker-compose

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