# module/standard.nix
# Standard Configuration Module for all Containers/Virtual Servers
{ config, pkgs, ...}:
{
  # Configure time
  time = {
    timeZone = "America/Chicago";
    hardwareClockInLocalTime = true;
  };
  # Configure Networking & Firewall
  networking = {
    hostName = "standard";
    networkmanager.enable = true;

    # Ensure firewall is enabled and allow SSH
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };
  # Configure Services
  services = {
    # Enable SSH
    openssh = {
      enable = true;

      settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
      };
    };
  };
  # Configure Packages & Programs
  environment.systemPackages = with pkgs; [
    vim
    bash
    shadow
  ];
  programs = {
    # Replace nano with Vim
    vim = {
      enable = true;
      defaultEditor = true;
    };
  };
  # Configure Users
  users = {
    mutableUsers = false;
    allowNoPasswordLogin = true;
    defaultUserShell = pkgs.bashInteractive;

    groups = {
      rnetadmin = {};
    };

    users = {
      root = {
        hashedPassword = "!";
        shell = "${pkgs.shadow}/bin/nologin";
      };

      rnetadmin = {
        hashedPassword = "$y$j9T$UZvqFZB/BrWJ2Y.1hs1ny0$aj0rH8cyJw3JCWf.MAD7v1mQ083wNeR5GX1mQPwpKU8";

        isSystemUser = true;
        createHome = true;
        group = "rnetadmin";
        extraGroups = [ "wheel" ];
        shell = pkgs.bashInteractive;

        openssh = {
          authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKLs7Ibr8m51iIUtjDSYSO/jegma3yRiwe+0Lf+lD+qM rnetadmin"
          ];
        };
      };
    };
  };
  # Security Settings
  security.sudo.enable = false;
  security.sudo-rs = {
    enable = true;
    wheelNeedsPassword = false;
  };
}