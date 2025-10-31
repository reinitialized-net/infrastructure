# modules/standard.nix
# Standard Configuration Module for all Containers/Virtual Servers
{ pkgs, inputs, ...}:
{
  # 1) Configure time
  time = {
    timeZone = "America/Chicago";
    hardwareClockInLocalTime = true;
  };
  # 2) Configure Networking
  networking = {
    networkmanager = {
      enable = true;
    };
    useNetworkd = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };
  # 3) Configure Services
  services = {
    openssh = {
      enable = true;

      settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
      };
    };
  };
  # 4) Configure Packages & Programs
  environment.systemPackages = with pkgs; [
    vim
    bash
    shadow
  ];
  programs = {
    vim = {
      enable = true;
      defaultEditor = true;
    };
  };
  # 5) Configure Users
  users = {
    mutableUsers = false; 
    allowNoPasswordLogin = true; # Required since we block interactive login for root to force usage of sudo.
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
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5pCeT2IuImFk0Rc2qcxudr8hVTgWvQDcwkXi0Hybru rnetadmin"
          ];
        };
      };
    };
  };
  # 6) Security Settings
  security = {
    # Replace sudo with sudo-rs
    sudo.enable = false;
    sudo-rs = {
      enable = true;
      wheelNeedsPassword = false;
    };
  };
  # 7) Nix Settings
  nix.settings = {
    # Enable automatic optimizations
    auto-optimise-store = true;
    # Enable flakes since they are soonTM
    experimental-features = [ "nix-command" "flakes" ];
    # Disable signature checks for now (look into proper fix)
    require-sigs = false;
	};
  # 8) Enable Automatic Security Upgrades
  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    dates = "02:00";
    randomizedDelaySec = "45min";
  };
  
  system.stateVersion = "25.05"; # LEAVE ALONE.
}

