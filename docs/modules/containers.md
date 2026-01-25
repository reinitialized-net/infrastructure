# Containers Profile Module

**Module Path:** `modules/profiles/containers/`

**Import:** Not automatically included - import explicitly

## Overview

Pre-configured Docker setup optimized for container orchestration with mesh networking support. Designed for NixOS hosts that will run Docker containers with shared storage and optional mesh network connectivity.

## Features

- Docker with optimized settings
- Automatic data partition mounting
- Mesh network integration
- cgroups v2 support
- Bind-mounted Docker data directory
- Dedicated Docker user/group

## Prerequisites

**Required:**
- `modules/profiles/mountData.nix` must be imported (enforced by assertion)

**Optional:**
- `modules/profiles/meshNetwork` for container mesh networking

## What It Configures

### Docker

```nix
virtualisation.docker = {
  enable = true;
  daemon.settings = {
    icc = true;  # Inter-container communication
    no-new-privileges = true;  # Security hardening
  };
};

virtualisation.oci-containers.backend = "docker";
```

### Storage

Bind mounts Docker data to persistent storage:

```nix
fileSystems."/var/lib/docker" = {
  device = "/mnt/data/docker";
  depends = [ "/mnt/data/docker/volumes" ];
  fsType = "none";
  options = [ "bind" ];
};
```

**Storage Layout:**
```
/mnt/data/docker/           # Docker root
  ├── volumes/              # Docker volumes
  ├── containers/           # Container data
  ├── image/               # Image layers
  └── ...                  # Other Docker data
```

### System Configuration

- **cgroups v2**: Enabled for modern container resource management
- **Docker user**: System user `docker` in group `docker`
- **Mesh Network**: Automatically imports mesh network module

## Usage

### Basic Setup

```nix
{
  imports = [
    ./modules/profiles/mountData.nix
    ./modules/profiles/containers
  ];
}
```

### With Mesh Network

```nix
{
  imports = [
    ./modules/profiles/mountData.nix
    ./modules/profiles/containers
  ];
  
  # Enable mesh networking
  services.meshNetwork = {
    enable = true;
    nodeId = 1;
    # Peers auto-discovered from meshTopology.nix
  };
}
```

### In a VM Image

```nix
{
  packages.x86_64-linux.docker-host = generateVMAImage "docker-host" {
    system = "x86_64-linux";
    vmId = 100;
    
    disks = [
      {
        storage = "local-lvm";
        size = 50;  # OS disk
      }
      {
        storage = "local-lvm";
        size = 500;  # Data disk for containers
      }
    ];
    
    modules = [
      ./modules/profiles/mountData.nix
      ./modules/profiles/containers
      {
        services.meshNetwork.enable = true;
        services.meshNetwork.nodeId = 1;
      }
    ];
  };
}
```

**Note:** Use `makeDualExport` instead for new systems.

## Docker Usage

### Running Containers

Standard Docker commands work as expected:

```bash
# Run a container
docker run -d --name nginx nginx:latest

# With volumes
docker run -d \
  --name postgres \
  -v postgres-data:/var/lib/postgresql/data \
  postgres:15

# With mesh network
docker run -d \
  --name app \
  --network backend \
  myapp:latest
```

### Docker Compose

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  web:
    image: nginx:latest
    ports:
      - "80:80"
    volumes:
      - web-data:/usr/share/nginx/html
    networks:
      - backend

  db:
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: secret
    volumes:
      - db-data:/var/lib/postgresql/data
    networks:
      - backend

volumes:
  web-data:
  db-data:

networks:
  backend:
    external: true  # Use mesh network if enabled
```

Deploy:

```bash
docker-compose up -d
```

### NixOS Container Definitions

Use `virtualisation.oci-containers` for declarative containers:

```nix
{
  virtualisation.oci-containers.containers = {
    nginx = {
      image = "nginx:latest";
      ports = [ "80:80" "443:443" ];
      volumes = [
        "/mnt/data/nginx/html:/usr/share/nginx/html:ro"
        "/mnt/data/nginx/conf:/etc/nginx/conf.d:ro"
      ];
      extraOptions = [ "--network=backend" ];
    };

    postgres = {
      image = "postgres:15";
      environment = {
        POSTGRES_PASSWORD = "secret";
        POSTGRES_DB = "myapp";
      };
      volumes = [
        "postgres-data:/var/lib/postgresql/data"
      ];
      extraOptions = [ "--network=backend" ];
    };
  };
}
```

## Storage Management

### Data Persistence

All Docker data is stored on `/mnt/data/docker`, which is bind-mounted from the second disk (configured by mountData profile).

**Benefits:**
- Survives OS reinstalls (OS is on disk 1, data on disk 2)
- Easy to snapshot/backup
- Can be resized independently
- Shared across system rebuilds

### Volume Management

```bash
# List volumes
docker volume ls

# Inspect volume location
docker volume inspect postgres-data
# Location: /mnt/data/docker/volumes/postgres-data/_data

# Backup volume
tar -czf backup.tar.gz /mnt/data/docker/volumes/postgres-data

# Restore volume
docker volume create postgres-data
tar -xzf backup.tar.gz -C /mnt/data/docker/volumes/postgres-data
```

### Disk Space

Check Docker disk usage:

```bash
# Overall usage
docker system df

# Detailed usage
docker system df -v

# Clean up
docker system prune -a --volumes
```

Check data partition:

```bash
df -h /mnt/data
```

## Mesh Network Integration

When mesh networking is enabled, containers can communicate across physical hosts.

### Architecture

```
Host 1 (10.255.0.1)
  └── Container A (172.20.0.10)
       └── Can reach: 10.255.0.2, 10.255.0.3

Host 2 (10.255.0.2)
  └── Container B (172.20.0.20)
       └── Can reach: 10.255.0.1, 10.255.0.3

Host 3 (10.255.0.3)
  └── Container C (172.20.0.30)
       └── Can reach: 10.255.0.1, 10.255.0.2
```

### Example: Multi-Host Application

**Host 1: Web Server**

```nix
{
  services.meshNetwork.nodeId = 1;
  
  virtualisation.oci-containers.containers.web = {
    image = "nginx:latest";
    ports = [ "80:80" ];
    environment = {
      BACKEND_HOST = "10.255.0.2";  # API on host 2
      DB_HOST = "10.255.0.3";       # DB on host 3
    };
    extraOptions = [ "--network=backend" ];
  };
}
```

**Host 2: API Server**

```nix
{
  services.meshNetwork.nodeId = 2;
  
  virtualisation.oci-containers.containers.api = {
    image = "myapi:latest";
    ports = [ "8080:8080" ];
    environment = {
      DB_HOST = "10.255.0.3";  # DB on host 3
    };
    extraOptions = [ "--network=backend" ];
  };
}
```

**Host 3: Database**

```nix
{
  services.meshNetwork.nodeId = 3;
  
  virtualisation.oci-containers.containers.postgres = {
    image = "postgres:15";
    ports = [ "5432:5432" ];
    volumes = [ "db-data:/var/lib/postgresql/data" ];
    extraOptions = [ "--network=backend" ];
  };
}
```

## Configuration Options

### Docker Daemon Settings

Override default Docker settings:

```nix
{
  virtualisation.docker.daemon.settings = {
    # Logging
    log-driver = "json-file";
    log-opts = {
      max-size = "10m";
      max-file = "3";
    };
    
    # Storage
    storage-driver = "overlay2";
    
    # Network
    default-address-pools = [
      {
        base = "172.20.0.0/16";
        size = 24;
      }
    ];
    
    # Security
    no-new-privileges = true;
    icc = true;
    userland-proxy = false;
  };
}
```

### Resource Limits

Configure cgroups resource limits:

```nix
{
  virtualisation.oci-containers.containers.myapp = {
    image = "myapp:latest";
    
    # Memory limit: 1GB
    extraOptions = [
      "--memory=1g"
      "--memory-swap=2g"
      "--cpus=2"
    ];
  };
}
```

## Security

### User Isolation

Containers run as the `docker` user (not root):

```nix
users.users.docker = {
  isSystemUser = true;
  group = "docker";
  home = "/var/lib/docker";
};
```

### Hardening

Default settings include:

- `no-new-privileges = true` - Prevents privilege escalation
- `icc = true` - Inter-container communication (controlled by networks)
- cgroups v2 - Better resource isolation

Additional hardening:

```nix
{
  virtualisation.oci-containers.containers.secure-app = {
    image = "myapp:latest";
    extraOptions = [
      "--read-only"                    # Read-only root FS
      "--tmpfs=/tmp"                   # Writable tmp
      "--cap-drop=ALL"                 # Drop all capabilities
      "--cap-add=NET_BIND_SERVICE"     # Add only needed caps
      "--security-opt=no-new-privileges:true"
    ];
  };
}
```

## Monitoring

### Docker Stats

```bash
# Real-time stats
docker stats

# One-time stats
docker stats --no-stream
```

### System Resources

```bash
# Disk usage
df -h /mnt/data

# Docker disk usage
docker system df

# Container logs
docker logs container-name
```

### Integration with Monitoring Systems

Export metrics for Prometheus:

```nix
{
  virtualisation.oci-containers.containers.cadvisor = {
    image = "gcr.io/cadvisor/cadvisor:latest";
    ports = [ "8080:8080" ];
    volumes = [
      "/:/rootfs:ro"
      "/var/run:/var/run:ro"
      "/sys:/sys:ro"
      "/var/lib/docker/:/var/lib/docker:ro"
    ];
  };
}
```

## Troubleshooting

### Check Docker Status

```bash
systemctl status docker
```

### Verify Storage Mount

```bash
mount | grep docker
# Should show: /mnt/data/docker on /var/lib/docker type none (rw,bind)
```

### Check Docker Info

```bash
docker info
```

### Test Mesh Connectivity (if enabled)

```bash
# From container to mesh network
docker run --rm --network backend alpine ping 10.255.0.2
```

### Common Issues

**1. Docker fails to start**
```bash
# Check if data directory exists
ls -la /mnt/data/docker

# Check permissions
sudo chown -R docker:docker /mnt/data/docker
```

**2. Can't access mesh network from containers**
```bash
# Verify mesh is enabled
systemctl status wireguard-wg-mesh

# Check nftables rules
nft list table inet mesh-docker
```

**3. Disk space issues**
```bash
# Clean up unused resources
docker system prune -a --volumes

# Check disk usage
df -h /mnt/data
```

## See Also

- [Mount Data Profile](mountData.md) - Required data partition mounting
- [Mesh Network Module](meshNetwork.md) - Container networking across hosts
- [Examples](../examples.md) - Complete configurations
