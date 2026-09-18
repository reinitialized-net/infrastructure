# Frigate cannot add the untrusted VLAN 14 cameras

Date: 2026-09-17

Two new TP-Link Tapo cameras on the untrusted VLAN (`10.1.14.2`, `10.1.14.3`)
could not be added to Frigate on apps3.

## Cause

Network reachability was not the problem. From apps3 and from inside the
`frigate` container, TCP connections to `10.1.14.2:554` (RTSP), `:2020` (ONVIF)
and `:443` succeed; the RTSP server answers `OPTIONS` and demands credentials
for realm `TP-Link IP-Camera`. Three things blocked the cameras:

1. **The configuration is Nix-managed.** `hosts/apps3/frigate.yml` is
   reinstalled on every `docker-frigate.service` start, so cameras added in the
   Frigate UI or config editor disappear at the next restart. Cameras must be
   added to that file and deployed with `rebuildHost apps3`.
2. **`10.1.14.3` has RTSP and ONVIF disabled.** Only `443/tcp` is open. Tapo
   cameras open `554` and `2020` only after a *Camera Account* is created in
   the Tapo app (Device Settings → Advanced Settings → Camera Account).
3. **No stream credentials existed** for either camera in the root-only env
   file `/var/lib/service-secrets/frigate.env`.

The existing camera at `10.1.13.37` was refusing connections during this
investigation. That is a separate device outage, not related to VLAN 14.

## Correction

- `hosts/apps3/frigate.yml` now declares `camera_14_2` and `camera_14_3`
  through go2rtc: `stream1` records, `stream2` feeds detection, both over RTSP
  TCP so the stateful VLAN firewall needs no RTSP helper or UDP return rules.
  Credentials are substituted from `FRIGATE_CAMERA_14_{2,3}_{USER,PASSWORD}`
  and never appear in YAML, Nix or Git. `camera_14_3` ships `enabled: false`
  until its Camera Account exists.
- `hosts/apps3/check_camera.py` checks every enabled camera instead of only
  `camera_13_37`, so the Docker health status covers the new cameras.
- Validated: exact-image (`frigate:0.18.0`) schema load of the new YAML with
  the custom detector plugin mounted, and the generalized health check
  executed inside the running container.

## Deployment (2026-09-17)

Both cameras use a dedicated Tapo Camera Account (a local RTSP/ONVIF login, not
the TP-Link cloud account) stored only in the root-only env file on apps3, with
a backup of the previous file beside it. They replace `camera_13_37`, which is
disabled rather than removed so its retained footage ages out normally.

Probed streams on both cameras: `stream1` H.264 2560x1440 at 20 fps (record),
`stream2` H.264 640x360 at 20 fps (detect at 5 fps). After `rebuildHost apps3`:
both cameras report 5 fps capture and detection with zero skipped frames,
OpenVINO inference is about 30 ms, the Docker health check passes, and motion
segments are being written for both cameras. A stale `.runtime_state.json`
override logs `Camera must be enabled in the config` for `camera_13_37` at
startup; it is harmless.

Still outside this repository and unverified here: OPNsense rules should allow
only `10.1.11.4` to VLAN 14 `554/tcp`, deny VLAN 14 initiated traffic to other
VLANs, and reserve both camera addresses. Storage: 30-day motion retention was
sized for one camera; measure growth with two 1440p cameras.
