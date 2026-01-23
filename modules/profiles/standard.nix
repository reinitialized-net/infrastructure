{
  lib,
  pkgs,
  ...
}: {
  time = {
    timeZone = lib.mkDefault "America/Chicago";
    hardwareClockInLocalTime = lib.mkDefault true;
  };

  networking = {
    hostName = lib.mkDefault "nixos-qemu";

    nftables.enable = lib.mkDefault true;
    networkmanager.enable = lib.mkForce false;
    useNetworkd = lib.mkForce true;
    useDHCP = lib.mkDefault false;

    firewall = {
      enable = lib.mkForce true;
      package = lib.mkForce pkgs.nftables;
    };
  };

  services.openssh = {
    enable = lib.mkForce true;
    settings = {
      PermitRootLogin = lib.mkForce "prohibit-password";
      PasswordAuthentication = lib.mkForce false;
      KbdInteractiveAuthentication = lib.mkForce false;
    };
  };

  environment.systemPackages = with pkgs; [
    bash
    shadow
    vim
  ];

  users = {
    mutableUsers = lib.mkForce false;
    allowNoPasswordLogin = lib.mkForce true;
    defaultUserShell = lib.mkDefault pkgs.bashInteractive;

    groups.rnetadmin = lib.mkDefault {};

    users = {
      root = {
        initialHashedPassword = lib.mkForce null;
        shell = lib.mkForce pkgs.bashInteractive;
      };
      rnetadmin = {
        # If this is used, it needs to be changed. 
        initialHashedPassword = lib.mkDefault "$6$ELaXwtqP5R5l.n5e$wsn7KBDXQKIfCbbDOfOHG4OYJjb/KQmyp4ekmFHcv/oZbJyEkwpoHCjqEDzOBpkGCXdZw1F1CNApXXkiKOhrR.";

        isSystemUser = lib.mkForce true;
        createHome = lib.mkForce true;
        group = lib.mkForce "rnetadmin";
        extraGroups = lib.mkDefault [ "wheel" ];
        shell = lib.mkForce pkgs.bashInteractive;

        openssh.authorizedKeys.keys = lib.mkDefault [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5pCeT2IuImFk0Rc2qcxudr8hVTgWvQDcwkXi0Hybru rnetadmin" ];
      };
    };
  };

  security = {
    sudo.enable = lib.mkForce false;
    sudo-rs = {
      enable = lib.mkForce true;
      wheelNeedsPassword = lib.mkDefault false;
    };
    polkit.enable = lib.mkDefault true;
  };

  nix.settings = {
    auto-optimise-store = lib.mkForce true;
    experimental-features = lib.mkForce [ "nix-command" "flakes" ];
    trusted-users = lib.mkForce [ "root" "rnetadmin" ];
  };

  system.autoUpgrade = {
    enable = lib.mkForce true;
    flake = lib.mkDefault "github:reinitialized.net/infrastructure";
    dates = lib.mkDefault "02:00";
    randomizedDelaySec = lib.mkDefault "45min";
  };
}