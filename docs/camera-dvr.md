# Camera DVR

Since 2026-09-17 the two Tapo gecko cameras record only while a detected
gecko is moving, using a locally trained one-class model; see
[Gecko detection and recording](gecko-tracking.md) for the design, training
data and results. The historical motion-only policy, motion sensitivity and
playback qualification below describe the retired `camera_13_37`.

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

Since 2026-09-17 the recorded cameras are two TP-Link Tapo units on the
untrusted VLAN 14 (`10.1.14.2`, `10.1.14.3`), pulled over RTSP TCP with a
dedicated camera account; see
[the VLAN 14 investigation](investigations/frigate-untrusted-vlan-cameras.md).
The original IP Webcam device at `10.1.13.37` is permanently offline; its camera
entry stays disabled with a ten-year motion retention so its footage remains
viewable (Frigate deletes recordings of cameras removed from the config). The
Tapo cameras appear in the UI as `Geckos1` and `Geckos2`. On 2026-09-18 the
02:30 fleet deploy reverted apps3 to `origin/indev` because the gecko commits
were only local; a local `rebuildHost` is not durable until pushed. Assign DHCP
reservations and provision dedicated stream credentials on cameras that support
them; restrict camera network access to the recorder and administration clients.

## Recording and storage

The requested policy is motion recording retained for 30 days, browsable through
Frigate's recording timeline. Time without motion has gaps; this is not 24/7
continuous coverage. Object detection uses OpenVINO on the VM's Intel CPU.
Motion analysis receives a 360x640, 5 fps decode stream; the
recording stream retains its original resolution without video transcoding.

The managed configuration shares the camera's original H.264 video through
one loopback go2rtc stream for recording and MSE live viewing
over the existing authenticated HTTPS/WebSocket proxy. The `Full resolution`
live stream avoids the 360x640 jsmpeg fallback and its video re-encoding. No
additional network ports are published. Smart Streaming idle images and the
debug view still use the low-resolution motion feed; open the live camera view
to assess full-resolution video.

### FFmpeg CPU and live quality remediation (2026-09-12)

The original combined record/detect input decoded 1080x1920 H.264 at 30 fps
in software even though motion analysis only needed 5 fps. Live measurements
showed 75.9% FFmpeg CPU. The VM's `bochs-drm` display device cannot accelerate
video decoding; no render node is available.

IP Webcam's `/shot.jpg` endpoint was verified to provide fresh 1080x1920 JPEGs.
Motion analysis now fetches these independently at 5 fps, then scales them to
360x640. `-re -loop 1 -framerate 5 -f image2` paces the requests before decoding;
wall-clock timestamps align motion metadata with recordings. Keep the input
framerate and `detect.fps` aligned when changing the analysis rate. This avoids
decoding the 30 fps H.264 recording stream. The snapshot endpoint is only for
analysis, never recording or full-resolution live viewing. It uses the same
camera and framing, without changing any camera encoder settings.

The recording process retains `-c:v copy`; the go2rtc MSE path likewise passes
through the original H.264 video. Raising motion resolution, reducing camera
bitrate/FPS, or suppressing the CPU warning is unnecessary. Smart Streaming
idle thumbnails and the debug view remain lower resolution; select the camera's
`Full resolution` live stream to assess quality. Old low-resolution previews
are not replaced by this change.

Frigate 0.18 persists live-view feature toggles in `/config/.runtime_state.json`
and replays them over YAML on restart. A saved `detect: true` override was found
during qualification; CPU object detection can skip analysis frames independently
of the now-low FFmpeg load. Motion recording does not require object detection.
Check effective runtime state, not just `detect.enabled` in YAML, when diagnosing
analysis performance.

References: [Frigate live view](https://docs.frigate.video/configuration/live/)
and [high CPU troubleshooting](https://docs.frigate.video/troubleshooting/cpu/).

Qualification for this remediation:

- Exact Frigate 0.18 image schema validation, pure apps3 host check, and apps3
  production-overlay toplevel build passed. Deployed closure:
  `/nix/store/nxnfh9nvisdi887dffwb38m35765d62z-nixos-system-apps3-26.05.20260911.21a67dc`.
- During a 65-second authenticated HTTPS MSE session, reported camera FFmpeg CPU
  was 3.0–6.0%, then 5.8–7.3% with the test viewer closed, versus 75.9% before.
  MSE delivered 121,294,460 bytes of original 1080x1920 H.264 at approximately
  30 fps. This exercises the real TLS/WebSocket proxy, not only loopback RTSP.
- A newly retained motion segment was 1080x1920 H.264 at 30 fps and approximately
  14.9 Mb/s. Packet SHA-256 comparison found 1,622 identical encoded video
  packets in authenticated live playback and retained recordings, confirming
  the same compressed video is preserved on both paths.
- Managed service restart qualification passed: authenticated MSE delivered a
  further 53,245,310 bytes at 1080x1920/30 fps; anonymous API access returned 401.
  Post-restart FFmpeg samples were 3.4–4.1%; an independent 10-second process
  CPU measurement totaled 7.4% across all four FFmpeg processes. Docker health
  and the storage guard passed, with no failed systemd units. The automatic
  rollback timer was canceled after these checks. Browser rendering itself was
  not manually exercised.
- With the saved CPU object-detection override active, busy samples skipped
  analysis frames; quiet samples sustained 5 fps with zero skipped frames.
  This is separate from the remediated FFmpeg decode warning.
- Rollback configuration and runtime environment backup are root-only under
  `/var/lib/frigate-deployment/20260912-cpu-quality/`. Only Frigate was restarted;
  camera encoder settings, retention policy, network exposure, and other
  application containers were unchanged.

### Object detector latency and live startup follow-up

The `Cpu is very slow (271.08 ms)` warning describes object inference, not
FFmpeg CPU or video FPS. The default three-thread TFLite detector was running
on a two-vCPU Intel Xeon E5-2690 v4 VM. CPU quota counters showed no throttling;
the slow inference backend was the limiting factor. Object detection remains
enabled and is now explicit in YAML, using the pinned image's bundled OpenVINO
SSDLite MobileNet V2 model on `CPU`, with its matching BGR/NHWC input and COCO
label map. No recording/live encoder, bitrate, resolution, or frame rate changed.

The stock OpenVINO runner still selected one inference thread on this VM's
two single-core virtual sockets and retained a 64.74 ms startup average. The
managed `openvino_cpu.py` detector adapter exposes two inference threads, one
inference stream, and disables CPU pinning. It reuses Frigate's SSD loader and
postprocessing, and initializes lazy kernels with three warmup calls before
accepting camera work. It does not alter measured inference times, warning
thresholds, video parameters, or the SSD model's weights. The plugin is mounted
read-only and discovered through Frigate's existing detector registry.

A 30-call adapter benchmark measured 16.3–48.9 ms. Exact-image qualification
checks detector registration, actual OpenVINO scheduling properties, invalid
GPU/thread settings, and output parity with the stock backend on three distinct
input patterns (tolerance 1e-5). Run `hosts/apps3/test_openvino_cpu.py` inside the
pinned Frigate image with `PYTHONPATH=/opt/frigate` and the plugin installed.
Requalify this adapter when upgrading Frigate; it uses the 0.18 runner API.
The change from the original TFLite detector to OpenVINO uses the bundled
SSDLite MobileNet V2 model; broad detection accuracy is not established by
these performance and backend-parity tests.

Six authenticated MSE startup measurements before this follow-up showed HTTPS
WebSocket handshakes of 0.09–0.21 seconds and first video of 1.25–3.69 seconds.
The original compressed stream must provide a keyframe before decoding can start.
A retained segment had 3.33-second keyframe gaps. The camera's ONVIF metadata is
inconsistent with actual video (including bitrate and GOP length); do not apply
its reported encoder values wholesale. ONVIF synchronization requests did not
demonstrate a reliable one-second keyframe cadence. The camera UI has no keyframe-interval setting. A separate on-demand RTSP
producer initially improved startup: authenticated first-video arrival measured
0.23–0.42 seconds in six tests, and one browser run decoded video after 0.9 seconds.
Other browser runs took 2.9–4.1 seconds. However, during the subsequent managed
restart test the camera stopped delivering both RTSP video and HTTP snapshots;
its status endpoint also stalled. Three direct snapshot requests still timed
out with Frigate completely stopped. The causal role of connection churn is
not established, but this failed recovery qualification, so the extra live
producer was withdrawn. The final config shares one persistent H.264 producer.
A device-side IP Webcam restart is required to resume live qualification.
Do not claim the startup delay or sustained inference warning fully resolved.

The adapter's initial production inference average settled at 54.14 ms, down
from 271.08 ms, while quiet analysis samples sustained approximately 5 fps with
zero skipped frames and FFmpeg CPU around 5–6%. Frigate's warning threshold is
50 ms and is unchanged; the retained average can still trigger its lesser
"slow" warning. Startup/steady-state motion qualification must be repeated after
camera recovery. Early short browser checks did not display a warning, but they
were not sufficient to establish that the status bar had received fresh stats.
A completed pre-failure 65-second MSE sample delivered 120,505,164 bytes of
1080x1920 H.264 at nominal 30 fps. This is evidence before the camera failure,
not proof of current camera availability. The headless browser decoded roughly
30 frames/s, with a few client-side dropped frames; no camera encoder or video
frame-rate settings were changed.

Final deployed closure for this follow-up:
`/nix/store/dl862s2pfyyqhrqfdqb32lzlrp9gaxql-nixos-system-apps3-26.05.20260911.21a67dc`.
The pure apps3 check, production-overlay toplevel build, detector parity tests,
and final-image configuration validation passed. The shared H.264 producer is
restored and the experimental live alias is absent. Frigate remains running,
ready to reconnect, but the camera was still returning no frames at handoff.
The rollback timer was canceled deliberately to retain the CPU improvements;
the prior system and manual rollback script remain root-only under
`/var/lib/frigate-deployment/20260912-openvino/`. No full-resolution/FPS reduction
or camera encoder-setting change was applied.

References: [Frigate object detectors](https://docs.frigate.video/configuration/object_detectors/)
and [upstream live-start investigation](https://github.com/blakeblackshear/frigate/discussions/15749).

### Camera recovery and portrait live metadata (2026-09-13)

The operator restarted IP Webcam and frames resumed. A 65-second authenticated
MSE capture received 124,043,438 bytes of 1080x1920 H.264 at nominal 30 fps.
FFmpeg stayed around 6–7% CPU; the quiet detector retained a 50.38 ms average.
An AAC-endpoint probe confirmed the same video dimensions/FPS and reported an
AAC decoding error. The video-only camera endpoint remains selected. Changing
audio formats did not establish a video-performance improvement.

Browser testing exposed a separate quality problem: IP Webcam's RTSP SDP
advertised stale landscape SPS metadata while the actual video was portrait.
The MSE browser consequently reported 3413x1920 display dimensions even though
ffprobe decoded 1080x1920 with square pixels. A normal MP4 remux displayed
correctly. A plain FFmpeg-to-RTSP copy retained the problem. Copying H.264
through an MPEG-TS pipe instead allowed go2rtc to read the actual in-band video
headers, and the browser then reported the correct 1080x1920 dimensions.

The managed go2rtc source now uses `ffmpeg:...#video=copy` and its FFmpeg output
template is `-f mpegts -`. This is remuxing, not video encoding, and shares one
persistent camera connection between live viewing and recording. The snapshot
analysis input, recording policy, camera resolution, bitrate and FPS are
unchanged. Temporary secondary stream/process tests used the existing local
restream and were removed by the managed activation.

Deployed closure:
`/nix/store/xhgkkyqrgfzmdfmgl5ac7lfgjhf5mf14-nixos-system-apps3-26.05.20260911.21a67dc`.
The apps3 pure check, production-overlay toplevel build, and exact-image YAML
validation passed. Dry activation identified only `docker-frigate.service` for
restart. The protected previous generation and rollback script are under
`/var/lib/frigate-deployment/20260913-stream-metadata/`.

On the deployed configuration, a 65-second authenticated MSE capture received
126,063,552 bytes. A retained 9.997-second segment was H.264, 1080x1920 at 30 fps,
and all 298 of its compressed packet hashes matched the corresponding live
capture. Chromium decoded approximately 30 fps at the correct portrait size;
4 of 1,051 frames were dropped by the headless client. FFmpeg's reported camera
CPU was 4.5–5.9%. During real detection work the inference average measured
36.77–48.98 ms, and the refreshed browser status bar showed no warning. Busy
analysis samples skipped 0.4–0.6 analysis frames/s before returning to zero;
this does not reduce the separately copied recording/live frame rate.

These observations do not establish a permanent sub-50 ms inference bound.
Spaced CPU benchmarks remained variable, and startup inference initially
exceeded 50 ms. No warning threshold, timing metric, or CPU model was changed
in this follow-up. Extra CPU capacity remains a possible next step if the
warning recurs. Live startup also still waits for a camera keyframe: the
deployed browser test started after 3.3 seconds. The recovered source's measured
keyframe intervals had a 1.67-second median with gaps up to 5 seconds, so the
startup delay is not fully resolved by the metadata correction.

The subsequent managed service restart recovered without restarting the camera.
Authenticated MSE delivered 60,257,650 bytes in the 35-second test; Chromium
started after 1.14 seconds and retained correct 1080x1920 display dimensions.
However, inference measured 56.57–66.26 ms during that qualification and settled
at 63.02 ms afterward. Thus the earlier warning-free sample did not establish
that the detector warning was fixed. Final quiet analysis sustained 5.1 fps
with zero skipped frames, zero reconnects/stalls, and excellent connection
quality. Camera FFmpeg CPU was 5.4%; a separate five-second process sample
totaled 15.4% across all FFmpeg processes, including the new copy-remux process.
Docker was healthy and no systemd units were failed. The timed rollback was
canceled after these checks to retain the verified video correction; its manual
rollback remains available. Temporary captured test media was removed. The
remaining detector warning requires further CPU-capacity investigation, for
which the operator was asked for the Proxmox management address.

### Four-core VM and post-boot access verification (2026-09-13)

The operator changed apps3 through the Proxmox UI to one socket with four cores
and restarted the VM. Live `lscpu` confirmed that topology. Frigate was reachable
and healthy when inspected following the reported outage; authenticated browser
playback also passed. Boot logs placed Docker startup at approximately 54–102
seconds and Frigate's service start at 104 seconds. There were no failed units
or Frigate restart-loop counts. These checks established recovery, not a
reproduction of the user's failed browser request.

Frigate still had its old two-CPU container limit. The managed limit is now four
CPUs, and the detector uses three inference threads without pinning. In spaced
benchmarks on the expanded VM, three threads had a 37.37 ms median versus
45.15 ms with two and 42.57 ms with four. Three threads leave CPU capacity for
video processing and the host's other services. The plugin accepts one through
four threads; its default and the managed YAML select three.

Deployed closure:
`/nix/store/aqsicllx3bwf2y4px3ilwfc2b5jwk76a-nixos-system-apps3-26.05.20260911.21a67dc`.
The pure apps3 check, production-overlay build, and two exact-image detector
qualification tests passed, including output parity against stock OpenVINO.
Only Frigate required a container restart. Runtime readback confirmed four CPUs
and three detector threads. During post-deployment active detection, inference
measured 31.04–34.69 ms and settled at 32.39 ms, with approximately 5.1 analysis
fps and no skipped frames, reconnects, or stalls in the samples. Reported camera
FFmpeg CPU was 5.4–6.1%. The refreshed browser displayed no warning.

Authenticated HTTPS MSE delivered 65,888,578 bytes during the 35-second test.
Chromium started video after 1.53 seconds and displayed 1080x1920 at approximately
30 fps, with two client-side drops among 1,050 frames. A newly retained segment
remained original H.264, 1080x1920 at 30 fps. Anonymous API access returned 401.
Docker health was healthy and there were no failed systemd units. The timed
rollback was canceled after verification; the protected previous generation and
manual rollback remain under `/var/lib/frigate-deployment/20260913-four-cpus/`.
Captured qualification media was removed. The camera-keyframe startup constraint
described above remains independent of this CPU-capacity improvement.

## Small-animal motion and recording seek tuning (2026-09-13)

The gecko enclosure uses motion-only retention by explicit owner choice; keep
`record.continuous.days: 0` and the existing 30-day motion retention. No hatchlings
are currently in view, so hatchling detection is not a validated field result.
The bundled COCO detector does not classify geckos; motion retention does not
require a recognized object. Object classification is now disabled only for this
camera (`detect.enabled: false`), with motion and recording explicitly enabled.
The pinned implementation evaluates motion before the object-detection branch
and still submits motion boxes for retention when classification is disabled.
This avoids blocking small-animal motion frames on unrelated classification.
The prior persisted `detect: true` toggle was changed through the authenticated
WebSocket command, backed up, and verified after restart. Do not add a
nonexistent gecko object label.

The previous motion defaults downscaled the portrait analysis image to 56x100.
The camera now uses `motion.frame_height: 320` (180x320), `threshold: 15`,
`contour_area: 5`, and contrast enhancement. The detection input remains 360x640
at 5 fps; live and recording remain original H.264 at 1080x1920 and 30 fps.
There are no motion masks that could exclude animals. This is a sensitivity
increase, not a guarantee against camouflage, occlusion, or movement between
analysis frames. Missing historical footage cannot be recovered by tuning.

In the exact running image, synthetic moving targets from 2x6 through 10x30
analysis pixels, with 20–30 grayscale-level contrast against a captured enclosure
background, were detected on all 25 test frames per target with the new settings;
the old defaults missed all of them. These are synthetic sensitivity checks,
not proof of detection of actual hatchlings. The 320-pixel motion height took
3.25 ms median / 3.84 ms p95 in that test. Full 640-pixel motion analysis also
passed but took 13.90 / 22.56 ms and was withdrawn after live capture showed
1.2–1.3 skipped analysis fps. The 320-pixel configuration also skipped frames
when classification ran; disabling unrelated classification was therefore needed
as well. A 10-second live profile found 77% of processing samples waiting for
frames and 9.5% waiting for inference, rather than CPU saturation alone.
Replaying three retained, low-motion clips at 5 fps
also found additional small changes, including lamp reflections; increased
sensitivity can retain more footage and must be considered when sizing storage.
The existing 100 GiB storage guard is unchanged.

Recording now targets five-second, source-keyframe-aligned MP4 segments instead
of ten. `-c copy -an` preserves the video bitstream; the configured source is
video-only. Source keyframe gaps can make files longer than five seconds. An
isolated remux test split a 300-packet recording into independently decodable
6.66- and 3.33-second files, preserved every packet hash in order, and retained
1080x1920 at 30 fps. Existing footage is untouched.

Authenticated HTTPS measurement found 16–43 MB playback segments and initial
manifest preparation of 0.15–1.24 seconds on older samples. The pinned Frigate
implementation probes the first file for a preceding keyframe when clipping a
playback range, and delivers chunks tied to recording-file durations. This is
not evidence of a ZFS fault: the guest sees ext4 on a rotational virtual disk,
and no host-pool settings were changed. Browser qualification using Frigate's
bundled HLS implementation and player buffer settings measured first decoded
frames at 1.15–1.69 seconds for three old samples versus 0.88–1.06 seconds for
three new samples. New samples transferred 10.1–15.7 MB versus 17.8–22.8 MB.
Buffered seeks took 0.16–0.20 seconds. These local-client samples do not guarantee
the same latency on every client or a cold disk; old files retain their original
segment lengths and keyframe spacing. A repeat while the intermediate
configuration was processing motion had old/new first-frame ranges of
0.98–1.72 / 0.73–1.41 seconds, with some new-sample seeks taking 0.54–1.19
seconds. Do not interpret the first test as a latency bound.

Final motion-only deployment: apps3 closure
`/nix/store/77xclvhgkm8wfy6c809xaiwpccgpv9cz-nixos-system-apps3-26.05.20260911.21a67dc`.
The pure apps3 check and production-overlay toplevel build passed, as did
exact-image configuration validation for the motion and recording settings.
All dry activations affected only Frigate. Post-restart API state confirmed
motion enabled, object classification disabled, 5 fps analysis, and zero-day
continuous / 30-day motion retention. Four live samples processed 5.1 fps with
zero skipped frames, no reconnects or stalls, camera FFmpeg CPU 5.4–6.5%, and
motion-process CPU 3.3–3.6%. The idle classifier's default 10 ms metric is not
an inference benchmark. New retained recordings with nonzero motion were
verified as H.264, 1080x1920, 30 fps. Authenticated Chromium live playback
rendered 1,049 frames over approximately 35 seconds, with five client-side
frame drops and no performance warnings; startup remained keyframe-dependent
(3.33 seconds in that sample). Docker was healthy, with zero container restarts
and no failed host units. The protected rollback, including the previous
runtime classification toggle, is under
`/var/lib/frigate-deployment/20260913-gecko-motion-only/`.
Final authenticated HLS checks on two post-restart recordings decoded first
frames in 0.97 and 1.37 seconds, with seeks of 0.17 and 0.60 seconds; transferred
13.9 and 15.5 MB. Old comparison samples transferred 17.8–22.8 MB and started
in 0.97–1.54 seconds. Smaller segments reduce transfer size; observed latency
overlaps and is still affected by keyframes, lookahead, and the client. Anonymous
API access remained 401. All task rollback timers were stopped after validation;
the storage guard remains active. Temporary qualification images were removed.

Motion setting reference: [Frigate motion tuning](https://docs.frigate.video/configuration/motion_detection/).

## Connection and motion regression investigation (2026-09-13 afternoon)

The 02:32:51 Infratainer deployment log confirms that apps3 was switched to
`nlqya07dfcdd7sq2x3dv97f24xwfyyn7` at approximately 02:37. Its managed configuration
predated the local Frigate fixes. The running camera consequently used the
direct combined RTSP input, 100-pixel motion height, threshold 30, contour area
10, ten-second recording segments, and a two-CPU container limit. The local
changes documented above had not been published to `indev`; scheduled deployment
from the remote branch replaced them. A successful local activation is not a
durable deployment until the matching source is published to the branch used
by both Infratainer and the host-local upgrade service.

There was also a separate camera stream failure. The API reported zero
`camera_fps`, 173 reconnects in an hour, and connection quality `unusable`, while
`process_fps` misleadingly retained 5.2 and Docker reported healthy. Logs showed
20-second capture watchdog retries and discarded empty recording segments.
Direct HTTP snapshots and status requests succeeded, and RTSP delivered packets,
but a 65-second direct sample contained 1,912 packets and **no keyframes**.
A separate decode attempt produced no frames within 15 seconds. This was not
an authentication failure or exhausted storage.

An ONVIF synchronization request returned HTTP 200 without restoring keyframes.
Reapplying the existing camera `video_size=1920x1080` setting briefly restored
keyframes and produced a decodable portrait recording, but did not provide
sustained recovery. The operator subsequently rebooted the camera. Neither
resolution, source FPS, nor bitrate was reduced. The precise internal cause of
IP Webcam's TCP streaming failure has not been established; a successful HTTP status
request or RTSP packet count does not establish that its video is usable.

The decisive transport comparison used the same camera and endpoint: UDP
delivered 362 packets with eight keyframes spaced approximately 1.666 seconds
apart over 12 seconds; the immediately following TCP probe delivered 354 packets
and no keyframes. Rebooting restored TCP playback briefly but did not make new
connections reliable. The managed go2rtc FFmpeg input now explicitly forces
`-rtsp_transport udp` on the camera leg. The existing MPEG-TS copy still corrects
portrait metadata, and recording and live clients still share that single camera
producer. Frigate's loopback RTSP connection remains TCP. No firewall or public
port exposure was broadened, and the video is not re-encoded. UDP was selected
because of this measured camera-specific TCP failure, not as a fleet-wide default.

Snapshot analysis recovered independently with the shared-stream configuration.
Further sensitivity tests against the current 360x640 enclosure snapshot found
that the prior 320-pixel-height, 15/5 settings detected only three of five
synthetic target sizes. The final settings keep height 320 and use threshold 10
and contour area 3. All five synthetic target sizes (2x6 through 10x30 pixels,
20–30 grayscale-level contrast) then registered on 25/25 frames per target.
The seeded low-amplitude noise sequence registered zero motion frames; processing
measured 2.58 ms median / 2.93 ms p95. Three retained low-motion clip replays
changed from 0/8, 0/8, and 65/83 motion frames to 0/8, 0/8, and 70/83.
These are sensitivity comparisons, not labeled gecko-accuracy measurements.
Reflections, lighting changes, camouflage, and occlusion remain relevant; tune
against real movement in representative day and night conditions. Continuous
retention remains zero days and motion retention remains 30 days.

Snapshot pacing was another independent contributor to missed motion. With the
image2 input's wall-clock timestamp option, 36 of 49 frame intervals in a
50-frame test were below 100 ms, with a 3 ms median and one-second gaps. Frigate
received approximately 5.6 fps but processed only 4.5–4.7 fps, dropping 0.9–1.1
fps despite low CPU use and disabled object classification. Removing
`-use_wallclock_as_timestamps 1` preserves image2's configured five-FPS timeline
and `-re` pacing: the comparison had a 200 ms median gap, 219 ms maximum gap,
and only two sub-100 ms intervals at startup. Raw detection frames are still
timestamped on capture by Frigate; recording timestamps use the separate RTSP
input. Increasing CPU or lowering motion sensitivity would not fix these bursts.

The snapshot input retains Frigate's capture watchdog: the pinned image2 demuxer
does not accept the generic `rw_timeout` input option. The YAML declares
the pinned configuration version explicitly so each start does not rerun legacy
configuration migrations. `check_camera.py` replaces the API-only Docker health
check with fresh capture statistics plus an eight-second keyframe probe of the
shared local recording stream. It does not open another camera connection, require
motion in a quiet scene, or automatically restart the camera. Three failed checks
mark the container unhealthy; Docker does not itself restart unhealthy containers.
The probe has a 20-second process timeout inside a 30-second health-check timeout,
a 60-second interval, and a 90-second startup grace period.

To check the actual video path without printing credentials:

```bash
ssh rnetadmin@10.1.11.4 'sudo docker exec frigate python3 /opt/frigate/check_camera.py'
ssh rnetadmin@10.1.11.4 'sudo docker inspect --format "{{.State.Health.Status}}" frigate'
```

For a future failure, check capture FPS and the keyframe probe separately. If
snapshots work but the recording probe fails, verify the source keyframes before
changing motion thresholds or restarting Frigate repeatedly. Source keyframe
recovery must be followed by a decodable new recording and authenticated live
playback. Missing historical video cannot be recovered from motion metadata.
See [Frigate live camera recommendations](https://docs.frigate.video/configuration/live/)
and [motion tuning](https://docs.frigate.video/configuration/motion_detection/).

Final deployed closure:
`/nix/store/f59pxf48lrq8wsdv1z7ybwznbfvfqwz6-nixos-system-apps3-26.05.20260911.21a67dc`.
The apps3 pure check, production-overlay toplevel build, exact-image configuration
validation, and both CPU-adapter tests passed. Each dry activation affected only
Frigate. The new health check failed against the broken TCP stream and passed
against the UDP-backed local restream. That local stream delivered eight periodic
keyframes in 12 seconds; runtime readback confirmed one camera producer using
UDP and video copy. Two newly retained five-second recordings each decoded 150
frames of 1080x1920 H.264 at 30 fps. Authenticated HLS checks on three new recordings
started in 0.90–1.34 seconds and sought in 0.14–0.15 seconds. Anonymous API access
remained 401. The stopped-service configuration/database backup and manual rollback
are root-only under `/var/lib/frigate-deployment/20260913-regression-repair/`.
The task rollback timer is stopped; the storage guard remains active.
After the final restart with fixed snapshot pacing, steady-state capture and
processing measured 5.0–5.1 fps with zero skipped frames, reconnects, or stalls.
Authenticated Chromium playback started in 1.25 seconds and rendered 1,057 frames
over approximately 35 seconds at 1080x1920, with six client-side frame drops and
no performance warnings. Docker's camera-aware health check passed, and the host
had no failed units. These bounded recovery checks do not establish long-term
Wi-Fi reliability or day/night gecko detection accuracy.

Configuration/database: `/mnt/data/frigate/config`.
Recordings, previews, and exports: `/mnt/data/frigate/media`.
Cache: 512 MiB tmpfs; shared memory: 256 MiB; container limit: 2 GiB / 4 CPUs.

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
`FRIGATE_CAMERA_13_37_URL`, `FRIGATE_CAMERA_13_37_SNAPSHOT_URL` (the camera's
HTTP `/shot.jpg` endpoint), `FRIGATE_CAMERA_14_2_USER`, `FRIGATE_CAMERA_14_2_PASSWORD`,
`FRIGATE_CAMERA_14_3_USER`, `FRIGATE_CAMERA_14_3_PASSWORD` (URL-encoded Tapo
Camera Accounts; see [the VLAN 14 investigation](investigations/frigate-untrusted-vlan-cameras.md)),
and a randomly generated `FRIGATE_JWT_SECRET`. Keep
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
