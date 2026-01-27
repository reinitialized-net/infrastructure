{
  lib,
  pkgs,
  ...
}: {
  time = {
    timeZone = lib.mkDefault "America/Chicago";
    hardwareClockInLocalTime = lib.mkDefault false; # Use UTC for RTC to avoid DST issues
  };

  # Enable NTP time synchronization
  services.timesyncd = {
    enable = lib.mkDefault true;
    servers = lib.mkDefault [
      "10.1.11.1"
    ];
  };

  networking = {
    hostName = lib.mkDefault "nixos-qemu";

    nftables.enable = lib.mkDefault true;
    networkmanager.enable = lib.mkForce false;
    useNetworkd = lib.mkForce true;
    useDHCP = lib.mkDefault true;

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

        isNormalUser = lib.mkForce true;
        createHome = lib.mkDefault true;
        group = lib.mkForce "rnetadmin";
        extraGroups = lib.mkDefault [ "wheel" ];
        shell = lib.mkForce pkgs.bashInteractive;

        openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5pCeT2IuImFk0Rc2qcxudr8hVTgWvQDcwkXi0Hybru rnetadmin" ];
      };
    };
  };

  security = {
    sudo.enable = lib.mkForce false;
    sudo-rs = {
      enable = lib.mkForce true;
      wheelNeedsPassword = lib.mkDefault false;
    };
    polkit = {
      enable = lib.mkDefault true;
      # Allow wheel group to manage systemd without authentication
      # Required for nixos-rebuild with sudo-rs over SSH
      extraConfig = ''
        polkit.addRule(function(action, subject) {
          if ((action.id == "org.freedesktop.systemd1.manage-units" ||
               action.id == "org.freedesktop.systemd1.manage-unit-files" ||
               action.id == "org.freedesktop.systemd1.reload-daemon") &&
              subject.isInGroup("wheel")) {
            return polkit.Result.YES;
          }
        });
        
        // Allow root user to manage systemd units (needed for sudo + systemd-run)
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.systemd1.manage-units" &&
              subject.user == "root") {
            return polkit.Result.YES;
          }
        });
      '';
    };
  };

  # Ensure polkit is properly started and rules are loaded
  systemd.services.polkit = {
    serviceConfig = {
      # Ensure polkit can read all rules
      ReadOnlyPaths = [
        "/etc/polkit-1/rules.d"
        "/run/current-system/sw/share/polkit-1/rules.d"
      ];
    };
  };

  # Allow wheel group to access systemd DBus without authentication
  services.dbus.packages = [ 
    (pkgs.writeTextFile {
      name = "nixos-rebuild-dbus-policy";
      destination = "/share/dbus-1/system.d/nixos-rebuild.conf";
      text = ''
        <!DOCTYPE busconfig PUBLIC
         "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
         "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
        <busconfig>
          <policy user="root">
            <allow send_destination="org.freedesktop.systemd1"
                   send_interface="org.freedesktop.systemd1.Manager"/>
            <allow send_destination="org.freedesktop.systemd1"
                   send_interface="org.freedesktop.DBus.Properties"/>
          </policy>
          <policy group="wheel">
            <allow send_destination="org.freedesktop.systemd1"
                   send_interface="org.freedesktop.systemd1.Manager"/>
            <allow send_destination="org.freedesktop.systemd1"
                   send_interface="org.freedesktop.DBus.Properties"/>
          </policy>
        </busconfig>
      '';
    })
  ];

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