#!/usr/bin/env python3
"""Bounded unauthenticated exposure checks for the explicitly authorized IPs.

Default lists the plan without networking. --run performs TCP connects and HEAD /
requests, with verified TLS/SNI, no redirects, proxies, credentials or body reads.
Run from an external network; an internal/hairpin vantage cannot prove WAN ACLs.
JSON lines are observations, not automated vulnerability verdicts.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import http.client
import json
import socket
import ssl

IPS = tuple(f"47.190.182.{last}" for last in range(76, 81))
# Source: hosts/rp1.nix. NAT mappings are external, so test each name at each IP.
PRIVATE = (
    "one.dns.reinitialized.net", "two.dns.reinitialized.net",
    "unifi.in.reinitialized.net", "pgadmin.in.reinitialized.net",
    "redisadmin.in.reinitialized.net", "jaeger.in.reinitialized.net",
    "grafana.in.reinitialized.net", "prometheus.in.reinitialized.net",
    "gs.admin.reinitialized.net", "search.reinitialized.net",
)
PUBLIC = (
    "mail.reinitialized.net", "docs.reinitialized.net",
    "www.docs.reinitialized.net", "media.reinitialized.me",
    "git.ds.reinitialized.net", "photos.reinitialized.me",
    "chat.reinitialized.me", "reinitialized.me",
    "admin.staging.bleupigs.club", "membership.staging.bleupigs.club",
    "accounts.staging.bleupigs.club", "docs.reinitialized.me",
    "access.reinitialized.net", "cloud.reinitialized.net",
    "ai.reinitialized.net",
)
# Configured ingress plus common accidental datastore/daemon/management ports.
# This is deliberately bounded, not an all-port or UDP scan.
PORTS = (22, 25, 53, 80, 143, 443, 465, 587, 993, 995, 1024, 1025,
         1027, 1028, 1029, 1031, 1032, 1037, 1039, 1040, 1041, 1042, 1043, 1044,
         2375, 2376, 3000, 3306, 4003, 4006, 4007, 4190, 5432, 6379,
         8080, 8096, 8443, 9000, 9090, 9200, 27017, 53443)


def observe(job):
    ip, port, host = job
    result = {"time_utc": datetime.now(timezone.utc).isoformat(),
              "ip": ip, "port": port, "host": host}
    if host:
        result["source_policy"] = "private clients only" if host in PRIVATE else "public ingress; application auth unverified"
    try:
        with socket.create_connection((ip, port), timeout=3) as raw:
            if not host:
                result["tcp"] = "connected"
                return result
            conn = ssl.create_default_context().wrap_socket(raw, server_hostname=host) if port == 443 else raw
            with conn:
                conn.settimeout(3)
                conn.sendall(f"HEAD / HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\nUser-Agent: infrastructure-exposure-audit\r\n\r\n".encode("ascii"))
                response = http.client.HTTPResponse(conn)
                response.begin()
                result["http_status"] = response.status
                response.close()
    except (OSError, ssl.SSLError, http.client.HTTPException) as error:
        result["error"] = str(error)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="perform the listed checks from this network vantage")
    args = parser.parse_args()
    plan = {"ips": IPS, "tcp_ports": PORTS, "private_names": PRIVATE,
            "public_ingress_names": PUBLIC, "http_methods": ["HEAD /"],
            "limitations": ["No UDP/DNS recursion test", "No application authentication test",
                            "No redirects or response bodies", "NAT mapping and deployed revision unverified"]}
    print(json.dumps({"plan": plan}), flush=True)
    if not args.run:
        return
    jobs = [(ip, port, None) for ip in IPS for port in PORTS]
    jobs += [(ip, port, host) for ip in IPS for host in PRIVATE + PUBLIC for port in (80, 443)]
    with ThreadPoolExecutor(max_workers=4) as pool:
        for result in pool.map(observe, jobs):
            print(json.dumps(result), flush=True)


if __name__ == "__main__":
    main()
