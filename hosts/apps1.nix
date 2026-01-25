{
  config,
  ...
}:{
  # Networking Configuration
  networking = {
    hostName = "apps1";
    useDHCP = false;
    firewall.whitelist = [
      # Allow DNS traffic
      {
        port = 53;
        protocol = "tcp_udp";
        ipType = "ipv4";
        source = [
          "0.0.0.0/0"
        ];
      }
      {
        port = 853;
        protocol = "tcp_udp";
        ipType = "ipv4";
        source = [
          "0.0.0.0/0"
        ];
      }
    ];
  };
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.11.2/24"
      ];
      dns = [
        "10.1.12.3"
        #"127.0.0.1"
        #"10.1.11.3"
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
      nodeId = 3;
  };
  # Hosted Services
  ## Docker-based Containers
  virtualisation.oci-containers.containers = {
    ### Hudu
    hudu_postgres1 = {
      autoStart = true;
      hostname = "hudu_postgres1";
      image = "docker.io/library/postgres:18-alpine";
      environment = config.secrets.hudu.keys;
      networks = [ 
        "backend"
      ];
      volumes = [
        "hudu_postgres1Data:/var/lib/postgresql/data"
      ];
    };
    hudu_redis1 = {
      autoStart = true;
      hostname = "hudu_redis1";
      image = "docker.io/library/redis:8-alpine";
      environment = config.secrets.hudu.keys;
      cmd = [ "redis-server" ];
      networks = [ 
        "backend"
      ];
      volumes = [
        "hudu_redis1Data:/var/lib/redis/data"
      ];
    };
    hudu1 = {
      autoStart = true;      
      hostname = "hudu1";
      image = "hududocker/hudu:latest";
      environment = config.secrets.hudu.keys;
      dependsOn = [
        "hudu_postgres1"
        "hudu_redis1"
      ];
      networks = [ 
        "backend"
      ];
      ports = [
        "10.255.0.3:3000:3000"
      ];
      volumes = [
        "hudu_data:/var/www/hudu2/public/uploads/"
        "hudu_data:/var/www/hudu2/uploads"
        "hudu_data:/var/lib/app/data"
      ];
    };
    hudu2 = {
      autoStart = true;
      hostname = "hudu2";
      image = "hududocker/hudu:latest";
      environment = config.secrets.hudu.keys;
      cmd = [ 
        "bundle" 
        "exec" 
        "sidekiq" 
        "-C" 
        "config/sidekiq.yml"
      ];
      dependsOn = [
        "hudu_postgres1"
        "hudu_redis1"
      ];
      networks = [ 
        "backend"
      ];
      volumes = [
        "hudu_data:/var/www/hudu2/public/uploads/"
        "hudu_data:/var/www/hudu2/uploads"
      ];
    };
    ### Technitium oneDns
    dnsOne = {
      autoStart = true;
      hostname = "dnsOne";
      image = "technitium/dns:14.3.0";
      networks = [
        "backend"
      ];
      volumes = [
        "technitium_data:/etc/dns"
      ];
    };
  };
}