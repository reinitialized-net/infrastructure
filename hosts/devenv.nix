# hosts/devenv.nix
## Defines configuration for the development environment VS.
{ pkgs, ...}:
{
  imports = [
    ./hardware/qemu.nix
    ./profiles/standard.nix
    ./modules/docker.nix
  ];

  # System-specific configuration
  networking.hostName = "devenv";
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "10.1.200.2";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = "10.1.200.1";
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

  ## Support vscode-server for remote ssh.
  ## TODO: look into alternative solutions. VSCode server??
  services.vscode-server.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    btop
    fastfetch
    docker-compose

    nixd
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