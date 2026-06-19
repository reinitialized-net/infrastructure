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

  # Workaround for systemd 258 + NixOS daemon-reexec DBus disconnect issue.
  # When switch-to-configuration triggers a daemon-reexec, systemd PID 1 can lose
  # its connection to the DBus system bus ("Got disconnect on API bus"), causing
  # systemd-run/systemctl and logind to fail. This happens because after reexec,
  # PID 1's serialized bus connection state becomes stale.
  #
  # Fix: A timer-triggered service that detects when org.freedesktop.systemd1 is
  # missing from the bus (indicating PID 1 lost its connection) and recovers by
  # restarting dbus and logind. This is safer than forcing dbus restarts during
  # switch-to-configuration (which NixOS upstream explicitly warns against).
  systemd.services.dbus-reconnect = {
    description = "Recover systemd DBus connection after daemon-reexec";
    after = [ "dbus.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecCondition = pkgs.writeScript "check-dbus-disconnect" ''
        #!${pkgs.bash}/bin/bash
        # Check if org.freedesktop.systemd1 is missing from the bus
        # If busctl can see it, the connection is fine — exit 1 to skip
        if ${pkgs.systemd}/bin/busctl --system list --no-pager 2>/dev/null | grep -q "org.freedesktop.systemd1"; then
          exit 1
        fi
        # systemd1 missing from bus — need recovery
        exit 0
      '';
      ExecStart = pkgs.writeScript "dbus-reconnect" ''
        #!${pkgs.bash}/bin/bash
        echo "dbus-reconnect: org.freedesktop.systemd1 not found on bus, restarting dbus to recover..."
        ${pkgs.systemd}/bin/systemctl restart dbus.service
        sleep 2
        # Also restart logind as it loses its bus connection too
        ${pkgs.systemd}/bin/systemctl restart systemd-logind.service
        echo "dbus-reconnect: recovery complete"
      '';
    };
  };

  systemd.timers.dbus-reconnect = {
    description = "Periodically check for systemd DBus disconnect";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "30s";
      AccuracySec = "5s";
    };
  };

  nix.settings = {
    auto-optimise-store = lib.mkForce true;
    experimental-features = lib.mkForce [ "nix-command" "flakes" ];
    trusted-users = lib.mkForce [ "rnetadmin" ];
  };

  system.autoUpgrade = {
    enable = lib.mkForce true;
    flake = lib.mkDefault "git+https://git.ds.reinitialized.net/reinitialized.net/infrastructure.git?ref=indev";
    operation = lib.mkDefault "switch";
    dates = lib.mkDefault "05:00";
    randomizedDelaySec = lib.mkDefault "45min";
  };
}
