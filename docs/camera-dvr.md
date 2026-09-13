# Camera DVR

## Selection (2026-09-12)

Frigate is the selected FOSS recorder: an MIT-licensed Docker application with
local recording, motion retention, authenticated viewing, and a recording
timeline. It fits the existing NixOS OCI deployment without a new external
database. Frigate+ and cloud AI are not required or configured.

Alternatives considered: ZoneMinder is GPL-licensed and a viable traditional
NVR; Frigate's container configuration and timeline are a closer fit here.
Shinobi's CE/Pro licensing and maintenance split adds ambiguity for the explicit
FOSS requirement, so it was not selected.

Primary sources:

- [Frigate license](https://github.com/blakeblackshear/frigate/blob/v0.18.0/LICENSE)
- [Frigate installation](https://docs.frigate.video/frigate/installation/)
- [Recording and retention](https://docs.frigate.video/configuration/record/)
- [Authentication](https://docs.frigate.video/configuration/authentication/)
- [0.18.0 release](https://github.com/blakeblackshear/frigate/releases/tag/v0.18.0)
- [ZoneMinder license](https://github.com/ZoneMinder/zoneminder/blob/master/LICENSE)
- [Shinobi CE/Pro policy](https://hub.shinobi.video/articles/view/QDD2cqvbTekzhar)

## Placement and access

`apps3` runs `docker-frigate.service`; `rp1` serves
`https://cameras.in.reinitialized.net` with ACME TLS and the existing internal
source allowlist. DNS must resolve that name to `10.1.12.4` on the internal
network. The upstream `10.255.0.5:1030` only accepts `rp1`'s mesh address.
Frigate native login stays enabled; create separate viewer accounts in Settings.
Its unauthenticated API and go2rtc listeners bind container loopback so backend
containers cannot use them to bypass authentication. WebRTC and RTSP are not
published. Access requires the existing internal network or VPN path.

The online device at `10.1.13.37:8080` identifies itself as IP Webcam, and
advertises `rtsp://10.1.13.37:8080/h264.sdp`. The two offline cameras are not
configured until their addresses and stream support are known. Assign DHCP
reservations and provision read-only stream credentials on cameras that support
them; restrict camera network access to the recorder and administration clients.

## Recording and storage

The requested policy is motion recording retained for 30 days, browsable through
Frigate's recording timeline. Time without motion has gaps; this is not 24/7
continuous coverage. Object detection is disabled to avoid requiring accelerator
hardware. Motion analysis still receives a 360x640, 5 fps decode stream; the
recording stream retains its original resolution without video transcoding.

Configuration/database: `/mnt/data/frigate/config`.
Recordings, previews, and exports: `/mnt/data/frigate/media`.
Cache: 512 MiB tmpfs; shared memory: 256 MiB; container limit: 2 GiB / 2 CPUs.

Live capacity before deployment was 712 GiB free on apps3's 984 GiB data disk.
At 4 Mb/s, 30 days is about 1.30 TB continuous or 259 GB at 20% motion duty,
before overhead. Measure actual growth; 30 days is a retention target, not a
capacity guarantee. Additional cameras require recalculation.

The initial real-camera sample was approximately 14 Mb/s (53 MB over 31 seconds).
At that rate, 30 days of constant motion is approximately 4.5 TB. With the
100 GiB reserve, the initial available capacity supports roughly 14% motion
duty over 30 days, before previews, exports, and other services' growth. Keep
original quality for now; measure at least a full day before sizing additional
storage or adjusting the camera's encoder. No encoder settings were changed.

The minute-based `frigate-storage-guard.timer` stops Frigate if shared disk free
space falls below 100 GiB. Startup also checks the mounted data filesystem and
free space. This protects other services and preserves existing footage rather
than silently deleting recordings earlier than the requested window. If it
trips, expand/free storage, investigate growth, and start `docker-frigate` again.
The guard cannot reserve capacity against other services writing concurrently.
Exports are not automatically expired by Frigate retention; remove/export them
to archive deliberately. Do not rely on the recorder as the only incident copy.

## Configuration and operations

`hosts/apps3/frigate.yml` is authoritative and is installed at every service
start. UI configuration changes are temporary until reflected in that file.
The root-owned mode-0600 `/var/lib/service-secrets/frigate.env` on apps3 contains
`FRIGATE_CAMERA_13_37_URL` and a randomly generated `FRIGATE_JWT_SECRET`. Keep
credentials in runtime files, never in YAML, Nix values, CLI arguments or Git.
On initial startup Frigate prints a generated admin password in privileged logs;
change it through Settings after initial login. Never publish those logs.

Validate with `nix build path:.#checks.x86_64-linux.apps3
path:.#checks.x86_64-linux.rp1 --no-link --no-write-lock-file`. Production builds
require the external secrets overlay with `--impure`. Also validate YAML against
the exact container version, verify a real recorded segment and authenticated
playback, restart persistence, and rejection on unauthenticated/internal ports.

Frigate is pinned to 0.18.0 and excluded from host-local image auto-restarts.
Renovate updates carry `manual-update`: review release notes, stop Frigate, back
up the entire config directory including its SQLite database, and qualify the
candidate before migration. A NixOS generation rollback does not undo database
migrations; restore the matching stopped-service database backup if necessary.
Recordings remain on disk when rolling back the added service configuration.

## Deployment evidence (2026-09-12)

- Deployed apps3 closure
  `/nix/store/nlqya07dfcdd7sq2x3dv97f24xwfyyn7-nixos-system-apps3-26.05.20260911.21a67dc`
  and rp1 closure
  `/nix/store/s2gl99nrbm2ddd0c7al7yhbdk88gy3d9-nixos-system-rp1-26.05.20260911.21a67dc`.
- Pure host checks and production-overlay toplevel builds passed for both hosts;
  final apps3 build/check repeated after correcting incompatible Docker log
  options (the existing OCI module uses journald).
- Exact-image YAML validation passed. Pulled image digest:
  `sha256:9678a83a76e4730ac7d9ea7428370e32ae656d6b312aaad30d6c69f3fef14d35`.
- Both DNS resolvers return `10.1.12.4`; ACME issuance succeeded and HTTPS
  certificate validation passed. Anonymous authenticated-port API requests
  return 401. Direct access to the mesh published port from devenv times out;
  rp1 can connect. Container-address ports 5000, 5001, 1984, 8554 and 8555 refuse
  connections; only authenticated port 8971 accepts them.
- Live camera stream is H.264, 1080x1920 at 30 fps. Motion analysis sustains
  approximately 5 fps, with zero skipped frames in the observed sample.
- Real motion generated two retained segments totaling 52.96 MB. Authenticated
  HTTPS HLS master/media playlists and a 42,930,400-byte media segment were
  retrieved successfully. ffprobe confirmed the saved original-resolution H.264
  video. Quiet time did not add retained segments.
- A managed service restart preserved the database, recordings and JWT login;
  authenticated timeline playback passed again afterward. Docker health is
  healthy; no failed systemd units remained. Existing application container
  uptime was preserved. The storage guard timer is active and its check passed.
- Initial admin password was rotated through the authenticated HTTPS API.
  Username is `admin`; the new password is root-only on apps3 at
  `/var/lib/service-secrets/frigate-admin-password`. Retrieve using an authorized
  SSH session: `sudo cat /var/lib/service-secrets/frigate-admin-password`.
- Both activations used timed rollback. Timers were canceled after health
  verification; original generations and rollback scripts remain protected at
  `/var/lib/frigate-deployment/20260912/` on each host. No reboot was performed.

Remaining qualification: a full 30-day retention period cannot be established
by this short deployment test; actual daily storage growth must be measured.
Browser interaction was not manually exercised; the real authenticated HLS
playback path and media were verified programmatically. Offline cameras remain
unconfigured. Keep important exported footage in a separate backup/archive.
