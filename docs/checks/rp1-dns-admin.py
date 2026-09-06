#!/usr/bin/env python3
"""Exercise the evaluated rp1 stream routes using NGINX and loopback backends.

Usage: python3 docs/checks/rp1-dns-admin.py /path/to/nginx /tmp/rp1-stream.conf
Only test listeners accept PROXY headers, to simulate client source addresses.
"""

import pathlib
import re
import socket
import ssl
import subprocess
import sys
import tempfile
import time


def main():
    nginx, stream_path = sys.argv[1:]
    stream = pathlib.Path(stream_path).read_text()
    blocks = re.findall(r"(?ms)^(?:geo|map|upstream|server)\b.*?^}", stream)

    def server(endpoint):
        matches = [b for b in blocks if b.startswith("server ") and f"listen {endpoint};" in b]
        assert len(matches) == 1, endpoint
        return matches[0]

    reservations = [socket.socket() for _ in range(6)]
    for sock in reservations:
        sock.bind(("127.0.0.1", 0))
    front_one, front_two, dns_one, dns_two, mail, reject = [s.getsockname()[1] for s in reservations]
    config = [b for b in blocks if b.startswith(("geo ", "map "))]
    for address, port in [("10.1.12.2:443", front_one), ("10.1.12.3:443", front_two)]:
        config.append(server(address).replace(
            f"listen {address};",
            f"listen 127.0.0.1:{port} proxy_protocol; set_real_ip_from 127.0.0.1;",
        ))
    for name, port in [("dnsOneUI", dns_one), ("dnsTwoUI", dns_two), ("mailProxyProtocol", mail)]:
        config.append(f'upstream {name} {{ server 127.0.0.1:{port}; }}')
        config.append(f'server {{ listen 127.0.0.1:{port}; return "{name}"; }}')
    if "upstream rejectDnsAdmin" in stream:
        config.append(f"upstream rejectDnsAdmin {{ server 127.0.0.1:{reject}; }}")
        config.append(server("127.0.0.1:8444").replace("127.0.0.1:8444", f"127.0.0.1:{reject}"))

    def client_hello(name):
        outgoing = ssl.MemoryBIO()
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname = False
        client = context.wrap_bio(
            ssl.MemoryBIO(), outgoing, server_hostname=name or None,
        )
        try:
            client.do_handshake()
        except ssl.SSLWantReadError:
            pass
        return outgoing.read()

    with tempfile.TemporaryDirectory(prefix="rp1-dns-admin-") as directory:
        path = pathlib.Path(directory) / "nginx.conf"
        path.write_text('daemon off; pid nginx.pid; error_log error.log;\nevents {}\nstream {\n'
                        + "\n".join(config) + "\n}\n")
        command = [nginx, "-p", directory + "/", "-c", str(path)]
        subprocess.run(command + ["-t"], check=True, capture_output=True)
        for sock in reservations:
            sock.close()
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            for _ in range(100):
                try:
                    with socket.create_connection(("127.0.0.1", front_one), timeout=0.1):
                        break
                except OSError:
                    assert process.poll() is None, process.stderr.read().decode()
                    time.sleep(0.02)
            else:
                raise AssertionError("NGINX did not start")

            def request(port, source, payload):
                with socket.create_connection(("127.0.0.1", port), timeout=2) as connection:
                    header = f"PROXY TCP4 {source} 127.0.0.1 12345 {port}\r\n".encode()
                    connection.sendall(header + payload)
                    try:
                        return connection.recv(128).decode()
                    except ConnectionResetError:
                        return ""

            sources = {
                "198.51.100.1": False, "9.255.255.255": False, "11.0.0.0": False,
                "172.15.255.255": False, "172.32.0.0": False,
                "192.167.255.255": False, "192.169.0.0": False,
                "10.0.0.0": True, "10.255.255.255": True,
                "172.16.0.0": True, "172.31.255.255": True,
                "192.168.0.0": True, "192.168.255.255": True,
            }
            names = ["one.dns.reinitialized.net", "two.dns.reinitialized.net", "unknown.invalid",
                     None, "mail.reinitialized.net", "MAIL.REINITIALIZED.NET"]
            cases = 0
            for source, private in sources.items():
                for name in names:
                    for port, dns in [(front_one, "dnsOneUI"), (front_two, "dnsTwoUI")]:
                        expected = dns if private else ""
                        if port == front_one and name and name.lower() == "mail.reinitialized.net":
                            expected = "mailProxyProtocol"
                        actual = request(port, source, client_hello(name))
                        assert actual == expected, (source, name, dns, expected, actual)
                        cases += 1
            for port in (front_one, front_two):
                assert request(port, "198.51.100.1", b"not TLS\r\n") == ""
                cases += 1
            print(f"PASS: {cases} source/SNI cases; DNS admin restricted, public mail preserved")
        finally:
            process.terminate()
            process.communicate(timeout=5)


if __name__ == "__main__":
    main()
