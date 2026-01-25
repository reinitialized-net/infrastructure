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
    in
    {
      packages.x86_64-linux.webserver = library.generateVMAImage "webserver" {
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
            
            networking.firewall.whitelist = [
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
    in
    {
      packages.x86_64-linux.database = library.generateVMAImage "database" {
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
          reinitialized-infra.inputs.self.nixosModules.default.imports # Get the modules
          ./secrets.nix
          {
            # Import mountData for data disk
            imports = [
              "${reinitialized-infra.inputs.self}/modules/profiles/mountData.nix"
            ];
            
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
            
            networking.firewall.whitelist = [
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

Three-node Docker cluster with mesh networking.

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
      
      # Shared configuration
      dockerHost = nodeId: extraModules: {
        cores = 4;
        memory = 16384;
        
        disks = [
          {
            storage = "local-lvm";
            size = 50;
          }
          {
            storage = "local-lvm";
            size = 500;  # Container storage
          }
        ];
        
        modules = [
          "${reinitialized-infra.inputs.self}/modules/profiles/mountData.nix"
          "${reinitialized-infra.inputs.self}/modules/profiles/containers"
          ./mesh-secrets.nix
          {
            services.meshNetwork = {
              enable = true;
              inherit nodeId;
            };
          }
        ] ++ extraModules;
      };
    in
    {
      packages.x86_64-linux = {
        docker-node1 = library.generateVMAImage "docker-node1" 
          ((dockerHost 1 [
            {
              networking.hostName = "docker-node1";
              
              # Web frontend
              virtualisation.oci-containers.containers.web = {
                image = "nginx:latest";
                ports = [ "80:80" "443:443" ];
                extraOptions = [ "--network=backend" ];
                environment = {
                  API_URL = "http://10.255.0.2:8080";
                };
              };
            }
          ]) // { system = "x86_64-linux"; vmId = 110; });
        
        docker-node2 = library.generateVMAImage "docker-node2"
          ((dockerHost 2 [
            {
              networking.hostName = "docker-node2";
              
              # API backend
              virtualisation.oci-containers.containers.api = {
                image = "myapi:latest";
                ports = [ "8080:8080" ];
                extraOptions = [ "--network=backend" ];
                environment = {
                  DATABASE_URL = "postgresql://10.255.0.3:5432/myapp";
                };
              };
            }
          ]) // { system = "x86_64-linux"; vmId = 111; });
        
        docker-node3 = library.generateVMAImage "docker-node3"
          ((dockerHost 3 [
            {
              networking.hostName = "docker-node3";
              
              # Database
              virtualisation.oci-containers.containers.postgres = {
                image = "postgres:15";
                ports = [ "5432:5432" ];
                extraOptions = [ "--network=backend" ];
                volumes = [
                  "postgres-data:/var/lib/postgresql/data"
                ];
                environment = {
                  POSTGRES_PASSWORD = "secret";
                  POSTGRES_DB = "myapp";
                };
              };
            }
          ]) // { system = "x86_64-linux"; vmId = 112; });
      };
    };
}
```

**`mesh-secrets.nix`:**

```nix
{
  secrets.meshNetwork = {
    description = "Docker cluster mesh network";
    
    keys = {
      # Node-specific IDs are set in the main config
      listenPort = 51820;
      
      peers = [
        {
          nodeId = 1;
          publicKey = "node1_public_key_here";
          endpoint = "192.168.1.10:51820";
        }
        {
          nodeId = 2;
          publicKey = "node2_public_key_here";
          endpoint = "192.168.1.11:51820";
        }
        {
          nodeId = 3;
          publicKey = "node3_public_key_here";
          endpoint = "192.168.1.12:51820";
        }
      ];
    };
  };
}
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
    in
    {
      packages.x86_64-linux.app-server = library.generateVMAImage "app-server" {
        system = "x86_64-linux";
        vmId = 120;
        cores = 4;
        memory = 8192;
        
        enableProtection = true;  # Enable Proxmox protection
        
        modules = [
          ./secrets.nix
          {
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
              whitelist = [
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
        ];
      };
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
      infra = reinitialized-infra.inputs.self;
    in
    {
      packages.x86_64-linux = {
        # Web server (public-facing)
        web = library.generateVMAImage "web" {
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
            infra.nixosModules.default
            ./secrets/mesh.nix
            ./modules/web.nix
          ];
        };
        
        # API server (internal)
        api = library.generateVMAImage "api" {
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
            infra.nixosModules.default
            ./secrets/mesh.nix
            ./secrets/apps.nix
            ./modules/api.nix
          ];
        };
        
        # Database server
        database = library.generateVMAImage "database" {
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
            infra.nixosModules.default
            ./secrets/mesh.nix
            ./secrets/apps.nix
            ./modules/database.nix
          ];
        };
        
        # Monitoring server
        monitoring = library.generateVMAImage "monitoring" {
          system = "x86_64-linux";
          vmId = 103;
          cores = 4;
          memory = 8192;
          
          modules = [
            infra.nixosModules.default
            ./secrets/mesh.nix
            ./modules/monitoring.nix
          ];
        };
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
  
  networking.firewall.whitelist = [
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
  
  networking.firewall.whitelist = [
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
  
  networking.firewall.whitelist = [
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
  
  networking.firewall.whitelist = [
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
