# Secrets Management Module

**Module Path:** `modules/profiles/secrets.nix`

**Import:** Automatically included with `nixosModules.default`

## Overview

The secrets module provides a centralized, declarative system for managing application secrets, API keys, credentials, and other sensitive configuration data in NixOS.

## Features

- Centralized secret definitions
- Key-value pairs for structured data
- File references for certificates, keys, etc.
- Type-safe configuration
- Integration with external secret managers (sops-nix, agenix, etc.)
- Auto-documentation through descriptions

## Option: `secrets`

### Type

```nix
attrsOf (submodule)
```

An attribute set where each attribute is a named secret containing:

### Submodule Options

#### `keys`

**Type:** `attrsOf anything`

**Default:** `{}`

**Description:** Key-value pairs for this secret. Keys can be any string, values can be any Nix type (strings, integers, booleans, lists, attribute sets).

**Example:**
```nix
secrets.my-service.keys = {
  apiKey = "sk_live_123456789";
  endpoint = "https://api.example.com";
  timeout = 30;
  retryCount = 3;
  enableDebug = false;
  headers = {
    "User-Agent" = "MyApp/1.0";
    "Accept" = "application/json";
  };
};
```

#### `file`

**Type:** `nullOr path`

**Default:** `null`

**Description:** Path to a file containing this secret. Useful for private keys, certificates, large files, or secrets managed by external tools.

**Example:**
```nix
secrets.wireguard.file = /run/secrets/wg-private-key;
secrets.tls.file = /run/secrets/server.key;
```

#### `description`

**Type:** `string`

**Default:** `""`

**Description:** Human-readable description of what this secret is for. Helps with documentation and understanding the configuration.

**Example:**
```nix
secrets.database.description = "PostgreSQL database credentials";
```

## Usage Examples

### Basic API Key

```nix
{
  secrets.github = {
    description = "GitHub API access";
    keys = {
      token = "ghp_xxxxxxxxxxxxxxxxxxxx";
      organization = "my-org";
    };
  };

  # Reference in other modules
  services.myapp.githubToken = config.secrets.github.keys.token;
}
```

### Database Credentials

```nix
{
  secrets.database = {
    description = "Production database";
    keys = {
      host = "db.example.com";
      port = 5432;
      database = "production";
      username = "app_user";
      password = "super_secret_password";
      sslMode = "require";
      poolSize = 20;
    };
  };

  # Use in services
  services.postgresql = {
    settings = {
      host = config.secrets.database.keys.host;
      port = config.secrets.database.keys.port;
    };
  };
}
```

### WireGuard Private Key

```nix
{
  secrets.wireguard = {
    description = "WireGuard VPN private key";
    file = /run/secrets/wg-privatekey;
    keys = {
      publicKey = "abc123...";
      endpoint = "vpn.example.com:51820";
    };
  };

  # Use in networking
  networking.wireguard.interfaces.wg0 = {
    privateKeyFile = config.secrets.wireguard.file;
  };
}
```

### Complex Application Configuration

```nix
{
  secrets.web-app = {
    description = "Web application configuration";
    keys = {
      session = {
        secretKey = "long-random-secret";
        cookieName = "app_session";
        lifetime = 3600;
      };
      
      smtp = {
        host = "smtp.gmail.com";
        port = 587;
        username = "noreply@example.com";
        password = "email_password";
        from = "noreply@example.com";
      };
      
      oauth = {
        google = {
          clientId = "123456.apps.googleusercontent.com";
          clientSecret = "secret";
        };
        github = {
          clientId = "Iv1.1234567890";
          clientSecret = "secret";
        };
      };
      
      features = {
        enableRegistration = true;
        enableOAuth = true;
        maxUploadSize = 10485760;  # 10MB
      };
    };
  };
}
```

### Mesh Network Configuration

```nix
{
  secrets.meshNetwork = {
    description = "WireGuard mesh network credentials";
    file = /run/secrets/mesh-privatekey;
    keys = {
      nodeId = 1;
      listenPort = 51820;
      peers = [
        {
          nodeId = 2;
          publicKey = "peer2_public_key";
          endpoint = "192.168.1.100:51820";
          persistentKeepalive = 25;
        }
        {
          nodeId = 3;
          publicKey = "peer3_public_key";
          endpoint = "192.168.1.101:51820";
          persistentKeepalive = 25;
        }
      ];
    };
  };

  # Automatically used by meshNetwork module
  services.meshNetwork.enable = true;
  # nodeId, privateKeyFile, and peers are auto-configured from secrets
}
```

## Integration with External Secret Managers

### With sops-nix

```nix
{
  # Import sops-nix
  imports = [ inputs.sops-nix.nixosModules.sops ];

  # Define sops secrets
  sops.secrets = {
    database-password = {
      sopsFile = ./secrets/db.yaml;
    };
    api-key = {
      sopsFile = ./secrets/api.yaml;
    };
  };

  # Reference in secrets module
  secrets.database = {
    description = "Database credentials (managed by sops)";
    keys = {
      host = "db.example.com";
      username = "app";
      # Password is in a file
    };
    file = config.sops.secrets.database-password.path;
  };

  secrets.api = {
    description = "API keys (managed by sops)";
    file = config.sops.secrets.api-key.path;
  };
}
```

### With agenix

```nix
{
  imports = [ inputs.agenix.nixosModules.age ];

  age.secrets = {
    wireguard-key.file = ./secrets/wg-key.age;
  };

  secrets.wireguard = {
    description = "WireGuard key (managed by agenix)";
    file = config.age.secrets.wireguard-key.path;
  };
}
```

### With Environment Variables

```nix
{
  secrets.runtime = {
    description = "Runtime environment secrets";
    keys = {
      apiKey = builtins.getEnv "API_KEY";
      debug = (builtins.getEnv "DEBUG") == "true";
    };
  };
}
```

## Best Practices

### 1. Never Commit Actual Secrets

Create a template file:

```nix
# modules/secrets.example/my-app.nix
{
  secrets.my-app = {
    description = "My application secrets";
    keys = {
      apiKey = "REPLACE_WITH_YOUR_KEY";
      endpoint = "https://api.example.com";
    };
  };
}
```

Copy and fill in actual values:

```bash
cp modules/secrets.example/my-app.nix modules/secrets/my-app.nix
# Edit with real values
# Add to .gitignore
```

### 2. Use Descriptions

Always add descriptions to make the code self-documenting:

```nix
secrets.service = {
  description = "External service API credentials - obtain from https://service.com/api";
  keys = { ... };
};
```

### 3. Structure Complex Secrets

Use nested attribute sets for related secrets:

```nix
secrets.infrastructure = {
  keys = {
    aws = {
      region = "us-west-2";
      accessKeyId = "...";
      secretAccessKey = "...";
    };
    cloudflare = {
      apiToken = "...";
      zoneId = "...";
    };
  };
};
```

### 4. Separate Development and Production

```nix
# flake.nix
{
  nixosConfigurations = {
    dev = makeConfiguration "dev" {
      modules = [ ./secrets/dev.nix ];
    };
    prod = makeConfiguration "prod" {
      modules = [ ./secrets/prod.nix ];
    };
  };
}
```

### 5. Use File References for Large Secrets

For certificates, keys, or large files:

```nix
secrets.tls = {
  description = "TLS certificates";
  file = /run/secrets/server.crt;
  keys = {
    # Store only metadata
    issuer = "Let's Encrypt";
    expiresAt = "2026-01-01";
  };
};
```

## Access Secrets in Configuration

```nix
{ config, ... }:
{
  # Direct access
  environment.variables.API_KEY = config.secrets.api.keys.token;

  # Conditional configuration
  services.myapp.enable = config.secrets ? myapp;
  services.myapp.apiKey = config.secrets.myapp.keys.apiKey or "";

  # File references
  services.wireguard.privateKeyFile = config.secrets.wireguard.file;

  # Nested values
  services.database = {
    host = config.secrets.db.keys.host;
    username = config.secrets.db.keys.username;
    password = config.secrets.db.keys.password;
  };
}
```

## Security Considerations

1. **File Permissions**: Secrets defined inline in Nix files will be world-readable in the Nix store
2. **Use File References**: For truly sensitive data, use `file` with proper permissions
3. **External Managers**: Consider sops-nix or agenix for encrypted secrets in version control
4. **Runtime Secrets**: Use systemd credentials or similar for runtime secret injection

## Examples in This Repository

See example secret configurations:

- [`modules/secrets.example/mesh.nix`](../../modules/secrets.example/mesh.nix) - Mesh network secrets
- [`modules/secrets.example/hudu.nix`](../../modules/secrets.example/hudu.nix) - Application secrets

## See Also

- [Mesh Network Module](meshNetwork.md) - Uses secrets for WireGuard configuration
- [Examples](../examples.md) - Complete usage examples
