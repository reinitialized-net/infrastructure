# Immich Server Crash: Mesh Key Mismatch & pgvector Extension Permission

## Symptoms

- `immich-server` container on apps3 was stuck in a restart loop
- Container would initialize but never reach healthy state
- Earlier restarts showed only "Initializing Immich v2.5.6" with no further output (hanging on DB connection)

## Root Causes

Two cascading issues were identified:

### 1. WireGuard Mesh Public Key Mismatch (Primary)

The apps3 public key in `meshTopology.nix` was incorrect. The value `YRxjbTedifIQ6nwZ2nGx4KTKOeXhRUUmpwZn+EWOBUU=` was recorded as the public key, but this was actually the **private key** stored in apps3's secrets. The actual public key (derived from that private key by WireGuard) was `OZEQjnEW/yhOLbVbBIcaQiiTojkuqTnO7n+oEqRbNDI=`.

**Evidence:**
- `sudo wg show` on apps3 showed public key `OZEQjnEW/yhOLbVbBIcaQiiTojkuqTnO7n+oEqRbNDI=`
- All peers showed `0 B received` — no peer accepted apps3's traffic
- `ping 10.255.0.11` (db1 mesh IP) from apps3 returned 100% packet loss

Since Immich connects to PostgreSQL and Redis via mesh IPs (`DB_HOSTNAME=10.255.0.11`, `REDIS_HOSTNAME=10.255.0.11`), the broken mesh caused the server to hang indefinitely waiting for a database connection.

### 2. pgvector Extension Not Created (Secondary)

Once the mesh was restored, Immich could reach PostgreSQL but crashed with:

```
FATAL [Microservices:DatabaseService] Failed to activate pgvector extension.
PostgresError: permission denied to create extension "vector"
hint: 'Must be superuser to create this extension.'
sql: 'CREATE EXTENSION IF NOT EXISTS vector CASCADE'
```

The `immich` database user lacks superuser privileges and cannot create PostgreSQL extensions. The `vector` extension (pgvector) must be created by a superuser.

## Steps to Identify

1. Read apps3 config — found Immich connects to `10.255.0.11` (db1 mesh IP) for DB and Redis
2. SSH'd to apps3 via VLAN IP (`10.1.11.4`) since mesh was down
3. `sudo docker ps -a` showed container constantly being recreated
4. `sudo wg show` revealed public key mismatch — actual key didn't match topology
5. Compared topology public key with secrets private key — identical value (copy-paste error)
6. After deploying mesh fix, `journalctl -u docker-immich-server` showed pgvector permission error

## Changes Made

### Fix 1: Corrected apps3 public key in mesh topology

**File:** `modules/profiles/meshNetwork/meshTopology.nix`

Changed apps3 `publicKey` from `YRxjbTedifIQ6nwZ2nGx4KTKOeXhRUUmpwZn+EWOBUU=` to `OZEQjnEW/yhOLbVbBIcaQiiTojkuqTnO7n+oEqRbNDI=`.

Deployed to all hosts via `updateInfra` so every peer updated their WireGuard config.

### Fix 2: Created pgvector extension as superuser

```bash
ssh rnetadmin@10.1.11.11 "sudo docker exec postgres1 psql -U postgres -d immich -c 'CREATE EXTENSION IF NOT EXISTS vector CASCADE;'"
```

This is a one-time operation. The extension persists in the database.

## Verification

- Mesh connectivity confirmed: `ping 10.255.0.5` from devenv returned 0% packet loss
- DB and Redis connectivity confirmed from inside the container
- `docker ps` showed immich-server as `(healthy)` after restart
- Logs confirmed both API and microservices workers started: `Immich Microservices is running [v2.5.6]`

## Lessons Learned

- When adding a new mesh node, always verify the public key by running `sudo wg show` on the host after deployment — never copy the private key value into the public key field
- The `mesh-keygen.sh` tool outputs both private and public keys; ensure the correct one is used in each location
- Database extensions required by applications (like pgvector for Immich) should be pre-created as superuser before deploying the application container
