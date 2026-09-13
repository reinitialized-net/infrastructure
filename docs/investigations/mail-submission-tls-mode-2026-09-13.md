# CMMC SMTP setup TLS mode mismatch

Date: 2026-09-13

The CMMC setup wizard reported `Hostname/IP does not match certificate's altnames: Cert does not contain a DNS name` with host `mail.reinitialized.net`, port `587`, and encryption `TLS`.

## Cause and correction

CMMC maps `TLS` to Nodemailer `secure: true` (implicit TLS). Port 587 expects an SMTP greeting followed by STARTTLS. Select **STARTTLS with port 587**, or **TLS with port 465**. Keep certificate verification enabled.

The misleading certificate error was reproduced using Nodemailer 9.1.1 extracted from the running CMMC bundle, under that container's Bun 1.3.13 runtime. No authentication credentials were supplied and no messages were sent.

| Port | Encryption | Bundled Nodemailer verification |
| --- | --- | --- |
| 587 | STARTTLS (`secure: false`, `requireTLS: true`) | Passed |
| 465 | TLS (`secure: true`) | Passed |
| 587 | TLS (`secure: true`) | Exact reported certificate error |

## Production evidence and scope

- The running CMMC container resolves `mail.reinitialized.net` to rp1 (`10.1.12.2`).
- Port 587 presents a Let's Encrypt certificate with SAN `DNS:mail.reinitialized.net`, valid August 14 through November 12, 2026, both with and without SNI.
- OpenSSL certificate and hostname validation passed on ports 465, 993, and 443. Direct Bun TLS checks from CMMC passed on 465 and STARTTLS on 587.
- rp1 remains the centralized ingress. The existing mail exception forwards TCP with PROXY protocol to Stalwart on apps1; Stalwart 0.15.4 handles mail TLS and STARTTLS using native ACME. See [the existing architecture](../architecture/stalwart-native-acme-tls.md).
- No production configuration, certificate, service, or application settings were changed. The wizard selection still needs to be changed by the operator. Account authentication and actual message delivery were not tested.

A reverse-proxy or certificate replacement is not required to correct this error.
