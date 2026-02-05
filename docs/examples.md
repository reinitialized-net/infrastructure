# Complete Usage Examples

This document provides complete, working examples for common use cases with this infrastructure flake.

## Table of Contents

1. [Simple Web Server VM](#simple-web-server-vm)
2. [Database Server with Large Disk](#database-server-with-large-disk)
3. [Multi-Host Docker Cluster](#multi-host-docker-cluster)
4. [Secure Application with Firewall](#secure-application-with-firewall)
5. [Complete Infrastructure Setup](#complete-infrastructure-setup)

---

## Simple Web Server VM

A basic web server VM with nginx.

### Configuration

**`flake.nix`:**

```nix
{
  description = "Simple web server";

  inputs = {
    reinitialized-infra.url = "github:reinitialized-net/infrastructure";
  };

  outputs = { self, reinitialized-infra }:
    let
      library = reinitialized-infra.lib;
      
      dualSystems = {
        webserver = library.makeDualExport "webserver" {
          system = "x86_64-linux";
          vmId = 100;
          cores = 2;
          memory = 4096;
          
          modules = [
            {
              services.nginx = {
                enable = true;
                virtualHosts."example.com" = {
                  root = "/var/www";
                  locations."/" = {
                    index = "index.html";
                  };
                };
              };
              
              networking.firewall.allowlist = [
                {
                  port = 80;
                  protocol = "tcp";
                  source = [ "0.0.0.0/0" ];
                }
                {
                  port = 443;
                  protocol = "tcp";
                  source = [ "0.0.0.0/0" ];
                }
              ];
            }
          ];
        };
      };
    in
    {
      nixosConfigurations.webserver = dualSystems.webserver.nixosSystem;
      packages.x86_64-linux.webserver = dualSystems.webserver.package;
    };
}
```

### Build and Deploy

```bash
# Build the image
nix build path:.#webserver

# Import to Proxmox
qmrestore result/vzdump-qemu-100.vma.zst 100 --storage local-lvm

# Start the VM
qm start 100
```

---

## Database Server with Large Disk

PostgreSQL database with a large data disk.

### Configuration

**`flake.nix`:**

```nix
{
  description = "PostgreSQL database server";

  inputs = {
    reinitialized-infra.url = "github:reinitialized-net/infrastructure";
  };

  outputs = { self, reinitialized-infra }:
    let
      library = reinitialized-infra.lib;
      
      dualSystems = {
        database = library.makeDualExport "database" {
          system = "x86_64-linux";
          vmId = 101;
          cores = 8;
          memory = 32768;
          
          disks = [
            {
              storage = "local-lvm";
              size = 50;  # OS disk
            }
            {
              storage = "data-pool";
              size = 1000;  # 1TB data disk
            }
          ];
          
          modules = [
            reinitialized-infra.nixosModules.default
            "${reinitialized-infra}/modules/profiles/mountData.nix"
            ./secrets.nix
            ./hosts/database.nix
          ];
        };
      };
    in
    {
      nixosConfigurations.database = dualSystems.database.nixosSystem;
      packages.x86_64-linux.database = dualSystems.database.package;
    };
}
```

**`hosts/database.nix`:**

```nix
{ config, pkgs, ... }: {
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_15;
    dataDir = "/mnt/data/postgres";
    
    settings = {
      max_connections = 200;
      shared_buffers = "8GB";
      effective_cache_size = "24GB";
    };
    
              authentication = ''
                host all all 10.0.0.0/8 md5
              '';
            };
            
            networking.firewall.allowlist = [
              {
                port = 5432;
                protocol = "tcp";
                source = [ "10.0.0.0/8" ];  # Internal network only
              }
            ];
          }
        ];
      };
    };
}
```

**`secrets.nix`:**

```nix
{
  secrets.database = {
    description = "Database credentials";
    keys = {
      superuserPassword = "change_me_in_production";
    };
  };
}
```

---

## Multi-Host Docker Cluster

Three-node Docker cluster with mesh networking using the autoPeers feature.

### Configuration

**`flake.nix`:**

```nix
{
  description = "Docker cluster";

  inputs = {
    reinitialized-infra.url = "github:reinitialized-net/infrastructure";
  };

  outputs = { self, reinitialized-infra }:
    let
      library = reinitialized-infra.lib;
      
      # Shared base configuration
      dockerHostBase = {
        cores = 4;
        memory = 16384;
        
        disks = [
          { storage = "local-lvm"; size = 50; }
          { storage = "local-lvm"; size = 500; }  # Container storage
        ];
      };
      
      dualSystems = {
        docker-node1 = library.makeDualExport "docker-node1" (dockerHostBase // {
          system = "x86_64-linux";
          vmId = 110;
          modules = [
            "${reinitialized-infra}/modules/profiles/mountData.nix"
            "${reinitialized-infra}/modules/profiles/containers"
            ./hosts/docker-node1.nix
          ];
        });
        
        docker-node2 = library.makeDualExport "docker-node2" (dockerHostBase // {
          system = "x86_64-linux";
          vmId = 111;
          modules = [
            "${reinitialized-infra}/modules/profiles/mountData.nix"
            "${reinitialized-infra}/modules/profiles/containers"
            ./hosts/docker-node2.nix
          ];
        });
        
        docker-node3 = library.makeDualExport "docker-node3" (dockerHostBase // {
          system = "x86_64-linux";
          vmId = 112;
          modules = [
            "${reinitialized-infra}/modules/profiles/mountData.nix"
            "${reinitialized-infra}/modules/profiles/containers"
            ./hosts/docker-node3.nix
          ];
        });
      };
    in
    {
      nixosConfigurations = {
        docker-node1 = dualSystems.docker-node1.nixosSystem;
        docker-node2 = dualSystems.docker-node2.nixosSystem;
        docker-node3 = dualSystems.docker-node3.nixosSystem;
      };
      
      packages.x86_64-linux = {
        docker-node1 = dualSystems.docker-node1.package;
        docker-node2 = dualSystems.docker-node2.package;
        docker-node3 = dualSystems.docker-node3.package;
      };
    };
}
```

**`hosts/docker-node1.nix`:**

```nix
{ config, ... }: {
  networking.hostName = "docker-node1";
  
  services.meshNetwork = {
    enable = true;
    nodeId = 1;
    # autoPeers = true (default) - peers auto-discovered from meshTopology.nix
  };
  
  # Web frontend
  virtualisation.oci-containers.containers.web = {
    image = "nginx:latest";
    ports = [ "80:80" "443:443" ];
    networks = [ "backend" ];
    environment = {
      API_URL = "http://10.255.0.2:8080";
    };
  };
}
```

**`hosts/docker-node2.nix`:**

```nix
{ config, ... }: {
  networking.hostName = "docker-node2";
  
  services.meshNetwork = {
    enable = true;
    nodeId = 2;
  };
  
  # API backend
  virtualisation.oci-containers.containers.api = {
    image = "myapi:latest";
    ports = [ "8080:8080" ];
    networks = [ "backend" ];
    environment = {
      DATABASE_URL = "postgresql://10.255.0.3:5432/myapp";
    };
  };
}
```

**`hosts/docker-node3.nix`:**

```nix
{ config, ... }: {
  networking.hostName = "docker-node3";
  
  services.meshNetwork = {
    enable = true;
    nodeId = 3;
  };
  
  # Database
  virtualisation.oci-containers.containers.postgres = {
    image = "postgres:15";
    ports = [ "5432:5432" ];
    networks = [ "backend" ];
    volumes = [
      "postgres-data:/var/lib/postgresql/data"
    ];
    environment = {
      POSTGRES_PASSWORD = "secret";
      POSTGRES_DB = "myapp";
    };
  };
}
```

**`modules/secrets/<hostname>.nix` (each node):**

```nix
{
  lib,
  ...
}: {
  secrets.meshNetwork = {
    description = "Mesh network credentials";
    # Private key is kept secret per-node
    file = lib.mkDefault (builtins.toFile "mesh-privatekey" "YOUR_PRIVATE_KEY_HERE");
  };
}
```

**Note:** With `autoPeers = true` (default), peers are automatically discovered from `meshTopology.nix`. You only need to configure the private key and nodeId per host.

### meshTopology.nix Configuration

Add all nodes to the centralized topology:

```nix
# modules/profiles/meshNetwork/meshTopology.nix
nodes = {
  docker-node1 = {
    nodeId = 1;
    hostname = "docker-node1";
    endpoint = "192.168.1.10:51820";
    publicKey = "node1_public_key_here";
  };
  docker-node2 = {
    nodeId = 2;
    hostname = "docker-node2";
    endpoint = "192.168.1.11:51820";
    publicKey = "node2_public_key_here";
  };
  docker-node3 = {
    nodeId = 3;
    hostname = "docker-node3";
    endpoint = "192.168.1.12:51820";
    publicKey = "node3_public_key_here";
  };
};
```

### Build All Nodes

```bash
# Build all three nodes
nix build path:.#docker-node1 path:.#docker-node2 path:.#docker-node3

# Import to Proxmox
qmrestore result-1/vzdump-qemu-110.vma.zst 110 --storage local-lvm
qmrestore result-2/vzdump-qemu-111.vma.zst 111 --storage local-lvm
qmrestore result-3/vzdump-qemu-112.vma.zst 112 --storage local-lvm

# Start all VMs
qm start 110
qm start 111
qm start 112
```

---

## Secure Application with Firewall

Application server with strict firewall rules.

### Configuration

**`flake.nix`:**

```nix
{
  description = "Secure application server";

  inputs = {
    reinitialized-infra.url = "github:reinitialized-net/infrastructure";
  };

  outputs = { self, reinitialized-infra }:
    let
      library = reinitialized-infra.lib;
      
      dualSystems = {
        app-server = library.makeDualExport "app-server" {
          system = "x86_64-linux";
          vmId = 120;
          cores = 4;
          memory = 8192;
          enableProtection = true;
          
          modules = [
            ./secrets/app-server.nix
            ./hosts/app-server.nix
          ];
        };
      };
    in
    {
      nixosConfigurations.app-server = dualSystems.app-server.nixosSystem;
      packages.x86_64-linux.app-server = dualSystems.app-server.package;
    };
}
```

**`hosts/app-server.nix`:**

```nix
{ config, pkgs, ... }: {
  # Application service
  systemd.services.myapp = {
    description = "My Application";
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python /opt/myapp/server.py";
      Restart = "always";
      User = "myapp";
    };
  };
  
  # Create app user
  users.users.myapp = {
    isSystemUser = true;
    group = "myapp";
    home = "/opt/myapp";
  };
  users.groups.myapp = {};
  
  # Strict firewall
  networking.firewall = {
    enable = true;
    
    # Only allow specific sources
    allowlist = [
      # HTTPS from CDN/load balancer only
      {
        port = 443;
        protocol = "tcp";
        source = [
          "203.0.113.0/24"  # Load balancer subnet
        ];
      }
      
      # SSH from admin network only
      {
        port = 22;
        protocol = "tcp";
        source = [
          "10.0.0.0/8"      # Internal network
          "192.168.1.100"   # Admin workstation
        ];
      }
      
      # Monitoring from Prometheus only
      {
        port = 9090;
        protocol = "tcp";
        source = [
          "10.255.0.100"    # Monitoring server
        ];
      }
      
      # Database access from app only
      {
        port = 5432;
        protocol = "tcp";
        source = [
          "10.100.0.0/24"   # App server subnet
        ];
      }
    ];
  };
  
  # Security hardening
  security.sudo-rs.wheelNeedsPassword = true;
  
  # Automatic security updates
  system.autoUpgrade = {
    enable = true;
    dates = "daily";
    allowReboot = false;
  };
}
```

---

## Complete Infrastructure Setup

Full infrastructure with web, API, database, and monitoring.

### Directory Structure

```
my-infrastructure/
├── flake.nix
├── secrets/
│   ├── mesh.nix
│   └── apps.nix
└── modules/
    ├── web.nix
    ├── api.nix
    ├── database.nix
    └── monitoring.nix
```

### Configuration Files

**`flake.nix`:**

```nix
{
  description = "Complete infrastructure";

  inputs = {
    reinitialized-infra.url = "github:reinitialized-net/infrastructure";
  };

  outputs = { self, reinitialized-infra }:
    let
      library = reinitialized-infra.lib;
      infra = "${reinitialized-infra}";
      
      dualSystems = {
        # Web server (public-facing)
        web = library.makeDualExport "web" {
          system = "x86_64-linux";
          vmId = 100;
          cores = 4;
          memory = 8192;
          
          networking = [
            {
              bridge = "vmbr0";
              vlan = 100;  # DMZ
              firewall = true;
            }
          ];
          
          modules = [
            reinitialized-infra.nixosModules.default
            ./secrets/mesh.nix
            ./modules/web.nix
          ];
        };
        
        # API server (internal)
        api = library.makeDualExport "api" {
          system = "x86_64-linux";
          vmId = 101;
          cores = 8;
          memory = 16384;
          
          networking = [
            {
              bridge = "vmbr0";
              vlan = 200;  # Internal
              firewall = true;
            }
          ];
          
          modules = [
            reinitialized-infra.nixosModules.default
            ./secrets/mesh.nix
            ./secrets/apps.nix
            ./modules/api.nix
          ];
        };
        
        # Database server
        database = library.makeDualExport "database" {
          system = "x86_64-linux";
          vmId = 102;
          cores = 16;
          memory = 65536;
          
          disks = [
            { storage = "local-lvm"; size = 50; }
            { storage = "data-ssd"; size = 2000; }
          ];
          
          networking = [
            {
              bridge = "vmbr0";
              vlan = 200;  # Internal
              firewall = true;
            }
          ];
          
          modules = [
            reinitialized-infra.nixosModules.default
            "${infra}/modules/profiles/mountData.nix"
            ./secrets/mesh.nix
            ./secrets/apps.nix
            ./modules/database.nix
          ];
        };
        
        # Monitoring server
        monitoring = library.makeDualExport "monitoring" {
          system = "x86_64-linux";
          vmId = 103;
          cores = 4;
          memory = 8192;
          
          modules = [
            reinitialized-infra.nixosModules.default
            ./secrets/mesh.nix
            ./modules/monitoring.nix
          ];
        };
      };
    in
    {
      nixosConfigurations = {
        web = dualSystems.web.nixosSystem;
        api = dualSystems.api.nixosSystem;
        database = dualSystems.database.nixosSystem;
        monitoring = dualSystems.monitoring.nixosSystem;
      };
      
      packages.x86_64-linux = {
        web = dualSystems.web.package;
        api = dualSystems.api.package;
        database = dualSystems.database.package;
        monitoring = dualSystems.monitoring.package;
      };
    };
}
```

**`modules/web.nix`:**

```nix
{ config, pkgs, ... }:
{
  services.meshNetwork = {
    enable = true;
    nodeId = 1;
  };
  
  services.nginx = {
    enable = true;
    
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    
    virtualHosts."api.example.com" = {
      enableACME = true;
      forceSSL = true;
      
      locations."/" = {
        proxyPass = "http://10.255.0.2:8080";  # API server via mesh
        proxyWebsockets = true;
      };
    };
  };
  
  networking.firewall.allowlist = [
    { port = 80; protocol = "tcp"; source = [ "0.0.0.0/0" ]; }
    { port = 443; protocol = "tcp"; source = [ "0.0.0.0/0" ]; }
  ];
  
  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@example.com";
  };
}
```

**`modules/api.nix`:**

```nix
{ config, pkgs, ... }:
{
  services.meshNetwork = {
    enable = true;
    nodeId = 2;
  };
  
  systemd.services.api = {
    description = "API Service";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    
    serviceConfig = {
      ExecStart = "${pkgs.nodejs}/bin/node /opt/api/server.js";
      Restart = "always";
      User = "api";
      
      Environment = [
        "DATABASE_URL=postgresql://10.255.0.3:5432/myapp"
        "PORT=8080"
      ];
    };
  };
  
  users.users.api = {
    isSystemUser = true;
    group = "api";
  };
  
  networking.firewall.allowlist = [
    {
      port = 8080;
      protocol = "tcp";
      source = [ "10.255.0.1" ];  # Web server only
    }
  ];
}
```

**`modules/database.nix`:**

```nix
{ config, pkgs, ... }:
{
  imports = [
    "${reinitialized-infra.inputs.self}/modules/profiles/mountData.nix"
  ];
  
  services.meshNetwork = {
    enable = true;
    nodeId = 3;
  };
  
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_15;
    dataDir = "/mnt/data/postgres";
    
    settings = {
      max_connections = 500;
      shared_buffers = "16GB";
      effective_cache_size = "48GB";
      work_mem = "32MB";
    };
    
    ensureDatabases = [ "myapp" ];
    ensureUsers = [{
      name = "myapp";
      ensureDBOwnership = true;
    }];
  };
  
  networking.firewall.allowlist = [
    {
      port = 5432;
      protocol = "tcp";
      source = [ "10.255.0.2" ];  # API server only
    }
  ];
}
```

**`modules/monitoring.nix`:**

```nix
{ config, pkgs, ... }:
{
  services.meshNetwork = {
    enable = true;
    nodeId = 4;
  };
  
  services.prometheus = {
    enable = true;
    port = 9090;
    
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{
          targets = [
            "10.255.0.1:9100"  # Web
            "10.255.0.2:9100"  # API
            "10.255.0.3:9100"  # Database
          ];
        }];
      }
    ];
  };
  
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_port = 3000;
        domain = "monitoring.example.com";
      };
    };
  };
  
  networking.firewall.allowlist = [
    {
      port = 3000;
      protocol = "tcp";
      source = [ "10.0.0.0/8" ];  # Internal network
    }
  ];
}
```

### Build and Deploy

```bash
# Build all services
nix build path:.#web path:.#api path:.#database path:.#monitoring

# Deploy to Proxmox
for vm in web api database monitoring; do
  qmrestore result-*/vzdump-qemu-*.vma.zst <vmid> --storage local-lvm
done

# Start infrastructure
qm start 100 && qm start 101 && qm start 102 && qm start 103
```

## See Also

- [Library Functions](library-functions.md) - Function documentation
- [Modules](modules/README.md) - Module documentation
- [Overview](overview.md) - Architecture overview
