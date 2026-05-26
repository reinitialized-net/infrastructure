# Mesh Network Port Reference

Reference for container services bound on WireGuard mesh IPs (`10.255.0.0/24`). Physical services such as DNS on port 53 and mail ingress through `rp1` are noted separately where relevant.

## apps1 (`10.255.0.3`)

| Port | Service | Protocol | Container port | Description |
|------|---------|----------|----------------|-------------|
| 1025 | `hudu1` | TCP | 3000 | Hudu web application |
| 1026 | `dnsOne` | TCP | 5380 | Technitium HTTP admin UI |
| 1027 | `dnsOne` | TCP | 53443 | Technitium HTTPS admin UI |
| 1028 | `dnsOne` | TCP/UDP | 53 | Technitium DNS service on mesh |
| 1029 | `stalwartOne` | TCP | 8080 | Stalwart HTTP/API/ACME listener |
| 1030 | `stalwartOne` | TCP | 25 | SMTP |
| 1031 | `stalwartOne` | TCP | 143 | IMAP |
| 1032 | `stalwartOne` | TCP | 465 | SMTPS |
| 1033 | `stalwartOne` | TCP | 587 | Submission |
| 1034 | `stalwartOne` | TCP | 993 | IMAPS |
| 1035 | `stalwartOne` | TCP | 995 | POP3S |
| 1036 | `stalwartOne` | TCP | 4190 | Sieve |
| 1037 | `forgejo` | TCP | 3000 | Forgejo web UI |
| 1038 | `jaeger` | TCP | 4317 | OTLP gRPC receiver |
| 1039 | `jaeger` | TCP | 16686 | Jaeger UI |
| 1040 | `grafana` | TCP | 3000 | Grafana web UI |
| 1041 | `stalwartOne` | TCP | 9090 | Prometheus metrics endpoint, if enabled |
| 1042 | `stalwartOne` | TCP | 443 | Stalwart HTTPS listener for TLS passthrough |
| 1043 | `authentik-server` | TCP | 9000 | Authentik web UI and API |

Next unused port after the highest current allocation: `1044`.

## apps2 (`10.255.0.4`)

| Port | Service | Protocol | Container port | Description |
|------|---------|----------|----------------|-------------|
| 1024 | `dnsTwo` | TCP | 5380 | Technitium HTTP admin UI |
| 1025 | `dnsTwo` | TCP | 53443 | Technitium HTTPS admin UI |
| 1026 | `dnsTwo` | TCP/UDP | 53 | Technitium DNS service on mesh |
| 1027 | `unifi` | TCP | 8443 | UniFi Network web admin |
| 1028 | `unifi` | UDP | 3478 | UniFi STUN |
| 1029 | `unifi` | UDP | 10001 | UniFi device discovery |
| 1030 | `unifi` | TCP | 8080 | UniFi device communication |
| 1031 | `pgadmin4` | TCP | 80 | pgAdmin4 web UI |
| 1032 | `redisInsight` | TCP | 5540 | Redis Insight web UI |
| 1040 | `cinny` | TCP | 80 | Cinny Matrix web client |

Unused gap: `1033`-`1039`. Next unused port after the highest current allocation: `1041`.

## apps3 (`10.255.0.5`)

| Port | Service | Protocol | Container port | Description |
|------|---------|----------|----------------|-------------|
| 1001 | `immich-server` | TCP | 2283 | Immich web UI and API |
| 1025 | `tuwunel` | TCP | 8008 | Matrix client/server API |
| 1026 | `paperless-ngx` | TCP | 8000 | Paperless-ngx web UI and API |
| 1027 | `pelican-panel` | TCP | 80 | Pelican Panel web UI |
| 1028 | `ocis` | TCP | 9200 | ownCloud Infinite Scale web UI and WebDAV |
| 1029 | `searxng` | TCP | 8080 | SearXNG web UI |

Next unused port: `1030`.

## ai1 (`10.255.0.9`)

No Docker container ports are declared in `hosts/ai1.nix`. The host allows `18789/tcp_udp` from private networks for the OpenClaw gateway.

`rp1` currently has an `ollama.in.reinitialized.net` proxy target of `http://10.255.0.9:1024`; verify the target service before changing or deploying that route.

## db1 (`10.255.0.11`)

| Port | Service | Protocol | Container port | Description |
|------|---------|----------|----------------|-------------|
| 1024 | `postgres1` | TCP | 5432 | PostgreSQL with pgvector |
| 1025 | `valkey1` | TCP | 6379 | Valkey cache |
| 1026 | `otel-collector` | TCP | 4317 | OTLP gRPC receiver |
| 1027 | `otel-collector` | TCP | 4318 | OTLP HTTP receiver |
| 1028 | `otel-collector` | TCP | 8889 | Prometheus exporter |
| 1029 | `prometheus` | TCP | 9090 | Prometheus web UI and API |

Next unused port: `1030`.

## gs1 (`10.255.0.6`)

`gs1` is defined in `hosts/gs1.nix` and `meshTopology.nix`, but is not exported from `flake.nix`.

| Port | Service | Protocol | Container port | Description |
|------|---------|----------|----------------|-------------|
| 1024 | `wings` | TCP | 8080 | Pelican Wings API, intended for Panel-to-Wings mesh traffic |

Physical host ports:

| Address/port | Protocol | Description |
|--------------|----------|-------------|
| `10.1.11.6:2022` | TCP | Wings SFTP |
| `10.1.11.6:25565-25600` | TCP/UDP | Game server range opened by host firewall for child containers |

Next unused mesh port: `1025`.

## Reverse Proxy Routes On `rp1`

Selected nginx routes from `hosts/rp1.nix`:

| Domain or listener | Upstream |
|--------------------|----------|
| `docs.reinitialized.net` | `http://10.255.0.3:1025` |
| `one.dns.reinitialized.net` HTTPS | stream passthrough to `10.255.0.3:1027` |
| `two.dns.reinitialized.net` HTTPS | stream passthrough to `10.255.0.4:1025` |
| `10.1.12.2:53443` | stream to `10.255.0.3:1027` |
| `10.1.12.3:53443` | stream to `10.255.0.4:1025` |
| `unifi.in.reinitialized.net` | `https://10.255.0.4:1027` |
| `pgadmin.in.reinitialized.net` | `http://10.255.0.4:1031` |
| `redisadmin.in.reinitialized.net` | `http://10.255.0.4:1032` |
| `git.ds.reinitialized.net` | `http://10.255.0.3:1037` |
| `jaeger.in.reinitialized.net` | `http://10.255.0.3:1039` |
| `grafana.in.reinitialized.net` | `http://10.255.0.3:1040` |
| `prometheus.in.reinitialized.net` | `http://10.255.0.11:1029` |
| `photos.reinitialized.me` | `http://10.255.0.5:1001` |
| `chat.reinitialized.me` | `http://10.255.0.4:1040` |
| `reinitialized.me` Matrix paths | `http://10.255.0.5:1025` |
| `docs.reinitialized.me` | `http://10.255.0.5:1026` |
| `gs.admin.reinitialized.net` | `http://10.255.0.5:1027` |
| `access.reinitialized.net` | `http://10.255.0.3:1043` |
| `cloud.reinitialized.net` | `http://ocis_backend`, currently `10.255.0.5:1028` |
| `search.reinitialized.net` | `http://10.255.0.5:1029` |

Mail protocols are proxied through nginx stream on `10.1.12.2` with PROXY protocol to Stalwart on apps1.

## Physical DNS Listeners

Technitium also binds directly on physical VLAN addresses:

| Host | Address | Ports |
|------|---------|-------|
| `apps1` | `10.1.11.2` | 53 TCP/UDP, 853 TCP/UDP, 67 UDP |
| `apps2` | `10.1.11.3` | 53 TCP/UDP, 853 TCP/UDP, 67 UDP |

`rp1` listens on public-facing DNS ports and stream-proxies to the Technitium backends.

## Allocation Guidelines

1. Prefer the next unused mesh port on the service host.
2. Keep protocol and container port explicit in `hosts/<host>.nix`.
3. Update this file whenever a mesh-facing port mapping changes.
4. Update `rp1.nix` when a service needs reverse proxy or stream ingress.
5. Update matching secret examples when new environment variables are required.

## Related Documentation

- [Port Mapping Scheme Migration](investigations/port-mapping-scheme-migration.md)
- [Technitium DNS Cluster Architecture](architecture/technitium-dns-cluster.md)
- [Mesh Network Module](modules/meshNetwork.md)
