{
  config,
  pkgs,
  ...
}:{
  # Networking Configuration
  networking = {
    hostName = "apps2";
    useDHCP = false;
  };
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.11.3/24"
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
  # Configure MeshNetwork
  services.meshNetwork = {
      enable = true;
      nodeId = 4;
  };

  # Enable ACME for DNS server certificate
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "admin@reinitialized.net";
    };
    certs."two.dns.reinitialized.net" = {
      # Use HTTP-01 challenge with webroot
      webroot = "/var/lib/acme/acme-challenge";
      # Ensure nginx user can read the certificates
      group = "nginx";
      # Reload Technitium container after cert renewal
      postRun = ''
        ${pkgs.docker}/bin/docker restart dnsTwo || true
      '';
    };
  };

  # Nginx for ACME challenge serving
  services.nginx = {
    enable = true;
    # Listen only on mesh network IP
    virtualHosts."two.dns.reinitialized.net" = {
      listen = [
        {
          addr = "10.255.0.4";
          port = 80;
        }
      ];
      locations."/.well-known/acme-challenge/" = {
        root = "/var/lib/acme/acme-challenge";
      };
    };
  };
  # Hosted Services
  ## Docker-based Containers
  virtualisation.oci-containers.containers = {
    ### Technitium oneDns
    dnsTwo = {
      autoStart = true;
      hostname = "dnsTwo";
      image = "technitium/dns-server:14.3.0";
      networks = [
        "backend"
      ];
      ports = [
        "10.255.0.4:5380:5380"
        "10.1.11.3:53:53/tcp"
        "10.1.11.3:53:53/udp"
        "10.1.11.3:853:853/tcp"
        "10.1.11.3:853:853/udp"
      ];
      volumes = [
        "technitium_data:/etc/dns"
        "/var/lib/acme/two.dns.reinitialized.net:/etc/dns/certs:ro"
      ];
    };
  };
}