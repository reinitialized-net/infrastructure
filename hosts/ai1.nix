{
  self,
  lib,
  system,
  ...
}:{
  # Networking Configuration
  networking = {
    hostName = "ai1";
    useDHCP = false;
  };
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.11.9/24"
      ];
      dns = [
        "10.1.11.2"
        "10.1.11.3"
      ];
      ntp = [
        "10.1.11.1"
      ];
      gateway = [
        "10.1.11.1"
      ];
      matchConfig.Path = "pci-0000:06:12.0";
    };
  };

  # Allow unfree packages for Ollama
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "open-webui"
  ];
  # Create dedicated ollama user
  users = {
    groups.ollama = {};

    users = {
      ollama = {
        isSystemUser = true;
        group = "ollama";
        description = "Ollama service user";
      };
    };
  };
  # Create required files
  systemd.tmpfiles.rules = [
    "d /mnt/data/models 0755 ollama ollama -"
  ];
  # Prevent ollama from using a DynamicUser
  systemd.services.ollama.serviceConfig.DynamicUser = lib.mkForce false;
  # Enable required services
  services = {
    meshNetwork.enable = true;

    ollama = {
      enable = true;
      package = self.inputs.nixpkgsOllama.legacyPackages.${system}.ollama;
      user = "ollama";
      group = "ollama";
      
      models = "/mnt/data/models"; 
    };
    open-webui = {
      enable = true;
      host = "10.255.0.9";
      port = 1024;
    };
  };
}
