# modules/standard.nix
# Standard Configuration module for all Containers/Virtual Servers
{ pkgs, lib, inputs, ...}:
{
  # Configure time
  time = {
    timeZone = "America/Chicago";
    hardwareClockInLocalTime = true;
  };
  # Configure Networking
  networking = {
    hostName = lib.mkDefault "standard";
    
    firewall.enable = lib.mkDefault true;
    networkmanager.enable = lib.mkDefault false;
    useNetworkd = lib.mkDefault true;
    useDHCP = lib.mkDefault true;
  };
  # Configure Services
  services = {
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
    vim = {
      enable = true;
      defaultEditor = true;
    };
  };
  # Configure Users
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
  # Security Settings
  security = {
    # Replace sudo with sudo-rs
    sudo.enable = false;
    sudo-rs = {
      enable = true;
      wheelNeedsPassword = false;
    };
  };
  # Nix Settings
  nix.settings = {
    # Enable automatic optimizations
    auto-optimise-store = true;
    # Enable flakes since they are soonTM
    experimental-features = [ "nix-command" "flakes" ];
    # Disable signature checks for now (look into proper fix)
    require-sigs = false;
	};
  system = {
    # Enable automatic security updates
    autoUpgrade = {
      enable = true;
      flake = inputs.self.outPath;
      dates = "02:00";
      randomizedDelaySec = "45min";
    };
    # Set system.stateVersion (!!!NEVER CHANGE THIS!!!)
    stateVersion = "25.05";
  };
}

