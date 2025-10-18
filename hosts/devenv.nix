# hosts/devenv.nix
## Defines configuration for the development environment VS.
{ pkgs, inputs, ...}:
{
  imports = [
    ../modules/standard.nix
    ../modules/docker.nix
    ../hardware/qemu.nix
    inputs.vscode-server.nixosModules.default
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

  ## Trial run openvscode-server
  services.openvscode-server = {
    enable = true;
    extraArguments = {
      "openvscode-server.port" = 8080;
    };
  };

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