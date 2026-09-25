# Gecko detection and recording

**Status (2026-09-19): four Tapo cameras share the gecko detector and recording
settings (`camera_14_2` = Geckos1, `camera_14_3` = Geckos2, `camera_14_5` =
Geckos3, `camera_14_14` = Geckos4).** Retention is 7 days continuous (required
24/7 recording) and 30 days active-gecko events; motion detection drives the timeline only. Geckos3 moved to `10.1.14.4`; its
original camera ID and secret names remain stable to preserve recording history.
Geckos4 is at DHCP-reserved `10.1.14.5`; its historical `camera_14_14` ID remains
stable to preserve recording history. Object detection is temporarily disabled on all four
by owner request while continuous recording is qualified; re-enable it for later
model testing. No new object events or boxed object snapshots are generated while
detection is paused. The section
directly below describes the deployed design. Everything from
"[Assessment (2026-09-13)](#gecko-detection-and-recording-assessment-2026-09-13)"
onward is the earlier investigation against the retired portrait camera
`camera_13_37`; its patched-recorder design and V7–V30 models were **not**
deployed and do not transfer to the new infrared views (V30 fired only on
static background there). The helper modules and patch bundle it produced are
still in `hosts/apps3/` but are unused by the running configuration.

## Four-camera connection verification (2026-09-19)

The apps3 toplevel build and pinned Frigate configuration validation passed.
After activation, all four effective detection, motion, object, review, snapshot,
and recording settings matched. Main streams delivered 2560x1440 H.264 and sub
streams 640x360 H.264, all with keyframes. Each camera produced a fresh recording
that decoded successfully; the container and camera health check passed.
Geckos3's live image and on-screen name matched its retained footage, confirming
the address move. Its camera ID was deliberately preserved.

Capture delivered approximately 5 fps per camera, but post-startup object analysis
processed roughly 0.8–2 fps and skipped remaining analysis frames under load.
This verification establishes connections and recording, not full-rate detection
or gecko recognition accuracy on the additional view. The 90-second Docker health
check timeout accommodates four sequential stream probes (up to 20 seconds each).

## Deployed design (2026-09-17)

The stock Frigate 0.18 pipeline already provides the recording rule the owner
asked for once a gecko class exists, so no Frigate source is patched:

- **Model.** A one-class YOLO11n (`hosts/apps3/gecko.onnx`, 320x320, ONNX
  opset 17, no built-in NMS) loaded by the existing `openvino_cpu` plugin, which
  now accepts `yolo-generic` in addition to SSD and still only overrides the
  CPU thread scheduling. Frigate runs one model, so every camera with
  detection enabled sees only the `gecko` label.
- **Grouping.** The gecko-specific configuration is written once on
  `camera_14_2` as a YAML anchor (`&gecko_camera`) and merged into
  `camera_14_3` with `<<: *gecko_camera`, which overrides only its own streams.
  A new gecko camera is added by copying the `camera_14_3` block
  (`camera_14_5` = Geckos3 was added this way). Frigate
  rejects unknown top-level keys, so the anchor cannot live in an `x-` template.
  `camera_groups.Geckos` groups all four cameras in the UI.
- **Detection input.** The 2560x1440 main stream, decoded at 1280x720 and
  5 fps (measured 0.27 CPU-core per camera; the 640x360 sub stream costs the
  same to decode but shrinks a gecko to ~25 px). Frigate feeds 320 px regions
  around motion, so a gecko is 50–100 px in the model input; training crops
  were built at exactly that scale.
- **Recording rule.** Per gecko camera: `record.motion.days: 0`,
  `record.continuous.days: 0`, alerts disabled, and
  `record.detections.retain.mode: active_objects` for 30 days with 5 s pre/post
  capture. Frigate keeps a segment only while a tracked gecko is *active*;
  `detect.stationary.threshold: 50` (10 s at 5 fps) plus the visual stationary
  classifier ends activity after ten still seconds without counting box jitter
  as movement. A stationary gecko stays tracked, so its next movement records
  immediately.
- **Motion.** `frame_height: 360`, `threshold: 20`, `contour_area: 10`,
  contrast enhancement, and a mask over the camera's timestamp overlay, whose
  changing digits otherwise generate constant motion.

### Training data and results

All training data came from the cameras' own first night (2026-09-17/18),
extracted from the motion recordings on apps3 with `sudo docker cp`; no
image left the owner's hosts. Labels were produced without hand-drawn boxes:

1. Frames at 2 fps from every retained segment, stored at 1280x720.
2. Foreground blobs against an all-night median background with a per-frame
   gain fit, a brightness-relative threshold, and a local
   normalised-cross-correlation gate so infrared exposure flicker on the bright
   hide and branch is ignored.
3. "Ghost" rejection: a blob whose region matches any of five period
   backgrounds is a gecko that rested long enough to be baked into the median
   and has since left. Ghosts are background, never labels.
4. A first model trained on those blobs was run over every frame; its
   detections were clustered by location and the clusters reviewed by eye, which
   recovered resting geckos the blob step could not see and identified the
   fixed false alarms (door latch, mesh edge, lamps, hide texture). The final
   model was trained on the agreement of both sources with those locations as
   hard negatives.

Positives per frame peak around the expected five geckos per tank. Results and
the deployed checksum are in the table below.

| Item | Value |
| --- | --- |
| Deployed model | `hosts/apps3/gecko.onnx`, SHA-256 `1441fe86e006ccf721a2098798f6ec5684f88d7607f223dfad31b60ddf6da83f` (YOLO11n, 320x320, round 4, from checkpoint `c5a70bbc…`) |
| Training rounds | R1–R3 (2026-09-17, night IR only, see below). R4 (2026-09-18): R3 fine-tuned 12 epochs on the night set plus a daylight set: 429 hand-verified colour gecko boxes from motion silhouettes (2 fps, 08:00–09:45 CDT), 1,241 hard-negative crops from 67 reviewed false-alarm zones (granite, floor glare, cork bark, timestamp digits, cables, a person), 1,340 clean background crops; colour augmentation (`hsv_s` 0.9) so one model serves IR and colour |
| Why R4 was needed | Every R1–R3 frame was greyscale IR (HSV saturation 0). In daylight R3 fired on granite, glare, bark and the timestamp digits at 0.6–0.89 while boxing real geckos by the head only; 477 of 1,200 daytime frames had a confirmed hit |
| R4 held-out daylight hour (10:00–11:00 CDT, 4,788 frames, never used for training or review) | 67 boxes ≥ 0.45 in 67 frames, all eight location clusters real geckos (max 0.63–0.87); the R3 paper-tag and bark clusters are gone |
| R4 on the training day (3,600 frames, 40 clusters ≥ 0.45) | 36 clusters real geckos incl. one under the red heat lamp (0.78); the four non-gecko clusters are a hand, an arm and a shirt at 0.45–0.55, below the 0.6 confirmation threshold |
| R4 on held-out night frames (428) | Same gecko clusters and scores as R3; no regression |
| R4 mixed validation (ultralytics, night labels are fragments) | precision 0.76, recall 0.64, mAP50 0.70 |
| R3 held-out metrics (ultralytics, 0.25 conf) | precision 0.84, recall 0.63, mAP50 0.74, mAP50-95 0.44 — measured against the semi-automatic labels, so recall is understated where labels are fragments |
| Known misses | geckos lying belly-down on the mesh floor of Geckos2 and animals seen only through two glass layers are often below 0.45; a gecko half hidden behind the Geckos2 wire label scored 0.57 |
| PyTorch vs Frigate OpenVINO parity | identical boxes (<0.01 px) on six crops (R3 export path, unchanged for R4); Frigate's stock YOLO post-processing drops anything under 0.4 |
| Live after deploy (2026-09-18 02:05) | model loaded, inference 26 ms, 12 gecko events with clips on both cameras in the first minute |

The two `objects.filters.gecko` values (`min_score: 0.45`, `threshold: 0.6`)
were chosen from these distributions: true geckos mostly score 0.7–0.9, the
remaining texture hits 0.45–0.58.

Retention (2026-09-22): the gecko cameras keep 7 days of continuous footage.
This is now an owner requirement, so do not restore it to 0 when detection
returns. Re-enabling detection also requires moving the detect role back to
the main stream at 1280x720 and re-enabling motion.

Retraining: the docker images and scripts are described in the memory note
on devenv; new gecko cameras should contribute a night of footage through the
same pipeline before their detection is trusted.

# Gecko detection and recording assessment (2026-09-13)


**Status: researched and behavior-probed; gecko-only recording is not enabled.**
The live camera still retains general motion for 30 days. No production
configuration, model, existing footage, or retention policy was changed by this
assessment. On September 14 the owner confirmed approximately seven adult
**Hemidactylus turcicus**; juveniles are not currently monitored. This supersedes the *requested* motion-only policy described in the
historical sections of [camera-dvr.md](camera-dvr.md), not its runtime evidence.

## Required behavior

The intended recording rule is a gecko-specific decision, not whole-frame motion:

- Start on a confirmed visible gecko, including one first seen sitting still.
- Continue while a confirmed gecko moves. Movement elsewhere must not extend it.
- End no later than 30 seconds after that gecko's last verified movement; for a
  newly detected still gecko, use the initial confirmation as the initial deadline.
- Presence alone must not repeatedly restart recording after the timeout.
  Verified renewed gecko movement can resume it. With multiple geckos, any
  qualifying gecko can keep the recording open.
- No unrelated motion recordings, idle preview videos, snapshots, audio events,
  or other scene-history artifacts. Gecko clips still contain their surroundings.
- Preserve the existing 30-day retention target, authenticated live view, original
  recording resolution, and scrubbable timeline with gaps between accepted clips.

For a strict interpretation of “up to 30 seconds,” the output must be bounded in
wall-clock time, not a number of processed frames. Missing/stale detections,
camera outages, detector crashes, and restart must not leave a recording open.
Confidence thresholds and any short occlusion allowance need validation against
ground truth; a model confidence score is not a measured probability of correctness.

## Verified current state

Read back from apps3's authenticated-container loopback API and installed source:

| Item | Observation |
| --- | --- |
| Image | `ghcr.io/blakeblackshear/frigate:0.18.0`; image ID `sha256:808254590862db209e363fba48a609d954a20ed98cceab51389616a1a3ba7f08` |
| Camera | `camera_13_37`; healthy; capture/process 5 fps, zero skipped frames in the inspected sample |
| Recording | Enabled; continuous 0 days; general motion 30 days |
| Object detection | Disabled; configured track label `person` |
| Installed model | SSD MobileNet V2, 300x300 COCO; installed label map contains neither gecko nor lizard |
| Custom model cache | No `.onnx`, `.pt`, `.xml`, or `.tflite` files found |
| Analysis | 360x640 snapshots, 5 fps; original source is portrait 1080x1920 |
| Scene | A current source snapshot showed strong red illumination, glass reflections, and obscuring enclosure furniture |

The scene observation is not an annotation or a detection-accuracy measurement.
Earlier synthetic small-motion tests also do not measure gecko recognition.

## Model options and the actual work required

Renaming a COCO class cannot teach the model geckos. Frigate's secondary
[object classification](https://docs.frigate.video/configuration/custom_classification/object_classification/)
operates on already detected objects, so it does not fix a missing base detector.
[Frigate+](https://docs.frigate.video/plus/#available-label-types) lists `lizard`
as an annotation candidate, not a supported detection label at the time checked.
It is not a verified gecko detector for this installation.

Public starting points exist:

- [TeddyChiu's gecko dataset](https://universe.roboflow.com/teddychiu/gecko-qxjbq)
  advertises 1,434 images and a Public Domain license. Inspect species, annotation
  quality, original images versus augmentation, and actual version exports before
  using it. This count is not evidence of independent examples or enclosure accuracy.
- [YOLOv11s Gecko & Towel](https://huggingface.co/lirou-0/yolov11s-gecko-towel)
  has a downloadable checkpoint at revision
  `7ccf0372fde01316765bfe1eac3d1856891da6df`. Its model card lists gecko/towel classes
  and a custom Roboflow dataset, but no accuracy results, species coverage, or
  license declaration. It was subsequently tested locally and rejected as supplied;
  see the September 14 experiment below. It has not been installed in production.

A practical local route is to fine-tune a small detector on bounding-box-labeled
footage from this enclosure. [YOLOX custom training](https://github.com/Megvii-BaseDetection/YOLOX/blob/main/docs/train_custom_data.md)
and its [OpenVINO export](https://github.com/Megvii-BaseDetection/YOLOX/blob/main/demo/OpenVINO/README.md)
provide one documented route; a compatible YOLO ONNX export is another.
This is a model-training and validation task, not a label-map edit.

Use actual day/red-light/night conditions, body sizes, poses, partial visibility,
climbing, slow head/tail movements, and every gecko to be covered. Include empty
views, hands, food insects, moving leaves, reflections, lighting changes, and
camera shake as negative examples. Keep images and annotations local. Split by
capture session/day **before** frame extraction/augmentation so near-identical
adjacent frames cannot inflate test results. Existing motion recordings can help
bootstrap training, but cannot establish recall for events motion capture missed.

Benchmark detection resolution and enclosure crops/tiling on the smallest target;
360x640 full-frame analysis may discard needed detail. Do not infer small-gecko
accuracy from large adults. Preserve the independent original H.264 recording
stream and test snapshot/video timing alignment.

The installed custom `openvino_cpu` adapter deliberately accepts SSD only. A YOLO
model needs a supported detector path, not removal of that guard. The pinned stock
OpenVINO class advertises `yolox` and `yolo-generic` support; actual preprocessing,
class indices, output decoding, exported-model equivalence, and inference speed
still need testing with the chosen artifact. Benchmark on apps3 within its current
four-CPU/2-GiB container limits before deciding whether acceleration is needed.
Do not train a model on the shared production recorder.

## Why stock recording settings do not meet the strict rule

Eight executable probes in
[probe_gecko_recording.py](../hosts/apps3/probe_gecko_recording.py) passed against
the running image's Python methods. They use synthetic metadata and replace media
writes with in-memory sinks. These are evidence of the following implementation
behaviors, **not** end-to-end recording or gecko-accuracy qualification:

1. General motion retention saves segments without any recognized object. Both
   continuous and general motion retention must be zero for object-only retention.
2. `motion` and `active_objects` retention discard fully quiet segments, including
   a desired quiet tail. `all` keeps the tail but requires a correctly bounded gate.
3. Review activity excludes false positives, other labels, stale frames, and
   stationary tracks. It also excludes a newly seen object that has never moved.
4. Review `end_time` is the last eligible activity time, not the time the review is
   closed. The review cutoff delays closure; it is not itself the saved tail.
5. An open review with `mode: all` can keep later quiet segments until it closes.
6. A segment overlapping the event window is retained whole. In the probe, a
   window from 100 to 130 seconds kept both 98–103 and 129–134 second segments even
   with zero pre/post capture. Five-second segment targets are not exact trim points.
7. Preview generation accepts unrelated motion and periodic idle frames even when
   full-quality retention is object-only.
8. `record.enabled: false` suppresses normal preview selection but not the first
   preview frame or conversion at the hour boundary in this pinned implementation.
   That first frame starts in RAM cache; the conversion path targets persistent
   `/media/frigate/clips/previews`. Simply toggling recording off does not establish
   the absence of all new persistent imagery.

Source paths checked: `frigate/record/maintainer.py`,
`frigate/review/maintainer.py`, `frigate/output/preview.py`,
`frigate/track/norfair_tracker.py`, and the corresponding config schemas.
For reference, [recording documentation](https://docs.frigate.video/configuration/record/)
describes capture windows and retention modes, and
[stationary-object documentation](https://docs.frigate.video/configuration/stationary_objects/)
describes the frame-count threshold. `150` frames at nominal 5 fps is not a hard
30-second deadline when processing slows or stops. Raising that threshold and
setting `post_capture: 30` can also count quiet time twice.

## Implementation and acceptance gates

Implement one gecko recording decision used by video retention, previews, and
scene-history metadata. Use confirmed gecko tracks and gecko-associated movement,
not global motion. A monotonic deadline and an independent stale-input watchdog
must close the gate without waiting for another camera frame. Stationary presence,
background motion, duplicate messages, and track ID churn must not reset it.
Keep input buffers bounded and temporary; clear them on restart. Generic motion
must never become the fallback for a failed model.

For strict persisted-video boundaries, evaluate segments before writing them to
persistent media. Trim/re-encode boundary GOPs, or discard boundary segments at the
cost of missing some gecko footage; ordinary stream-copy segmentation cannot
guarantee both exact cuts and complete edge footage. Qualify the chosen approach
against Frigate's database, authenticated playback, seeking, and cleanup. A plain
MQTT/WebSocket recording toggle or retention cleanup after the fact is insufficient.

Before enabling the gecko-only policy:

- Produce a versioned model, checksum, class map, dataset manifest/splits, inference
  settings, and manually reviewed annotations. Pin the trained artifact.
- Report event precision, visible-gecko movement recall, false clips per camera-day,
  start delay, and cutoff error on held-out sequences, separately by lighting and
  target size. Include sample counts and confidence intervals. Proposed accuracy
  targets are at least 99% precision and 99% recall; owner acceptance and enough
  independent examples are required before treating those as release criteria.
  Neither a confidence setting nor zero errors on a few clips proves these targets.
- Exercise first detection while still, prolonged immobility, head/tail-only motion,
  renewed movement before/after 30 seconds, disappearance, two geckos, reflections,
  handling/feeding, red-light transitions, detector failure, camera outage, low FPS,
  time changes, restart, and stale/duplicated events. No observed retained segment
  may extend beyond the deadline; test actual decoded timestamps and all media paths.
- Run inference without controlling production retention through representative
  day/night conditions, compare to independently labeled ground truth, then replay
  complete sequences through the candidate recorder. Additional qualification
  capture requires an explicit bounded dataset policy if ordinary recording is paused.
- Validate the exact image config and apps3 pure/production-overlay toplevel builds;
  deploy with rollback, verify live effective settings including persisted UI
  overrides, and audit new media plus UI/API playback. Publish matching source to
  the automation branch when deploying so scheduled updates cannot restore motion-only
  recording. Keep existing footage until its handling is explicitly decided.

The missing evidence is an enclosure-qualified gecko model and labeled evaluation
sequences, followed by a tested recording/preview implementation. No gecko accuracy
percentage or exact cutoff guarantee can currently be reported.

## September 14 candidate experiment

Live readback again confirmed detection disabled, `person` as the configured track
label, and 30-day general-motion retention. All eight upstream behavior probes
passed again; those probes expose unsuitable recording semantics, not gecko accuracy.

The `lirou-0/yolov11s-gecko-towel` checkpoint at the revision above was downloaded
and tested locally, outside production. Artifact SHA-256:
`6c08dabb1a467d13616ce834628be0cbca7ad78f00a19503a4eeb1a874c609e3`.
Its actual class map is `0: gecko`, `1: towel`. Inference ran in a disposable
container with networking disabled, read-only inputs/root filesystem, no host
credentials, two CPUs, and a 4-GiB memory limit. Camera images were not uploaded.

Inputs were twelve hourly samples from existing recordings, a current 360x640
analysis frame, and a current 1080x1920 source snapshot. Both 640- and 1280-pixel
inference sizes were tested at a diagnostic confidence floor of 0.05. These are
unlabeled exploratory samples, not a training set or an independent accuracy set.

**Candidate rejected as supplied:** in the daytime archive sample at Unix time
1789322813, 1280-pixel inference classified the large diagonal branch as `gecko`
with score 0.86103 and box approximately `(85, 794, 575, 1082)` in the original
1080x1920 image. Other frames also produced branch-sized gecko boxes. A higher
confidence threshold cannot be qualified without confirmed positive examples and
measurement of the geckos it would miss. No recognition success or recall estimate
can be claimed from this experiment. The model has not been installed in Frigate.

An additional eighteen 640x640 enclosure crops (six overlapping crops from each
of two daytime frames and the current full-resolution red-lit frame) did not
establish a usable detector. Daytime crops again produced branch-region boxes;
all six red-lit crops produced no gecko-class predictions at the 0.05 diagnostic
floor. These are not verified negatives: animal visibility still requires ground
truth. The owner subsequently identified the center-rock sequence described below.
That provides positive examples but does not qualify this public model.

Private working inputs, scripts, and raw inference results for this run are at
`/tmp/gecko-validation-20260914/` on the development host; this temporary directory
is not a durable dataset or a deployment artifact. No existing recording was
deleted or modified.

Re-run the non-mutating semantic probes from the repository:

```bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes rnetadmin@10.1.11.4 \
  'sudo docker exec -i -e PYTHONPATH=/opt/frigate frigate python3 -' \
  < hosts/apps3/probe_gecko_recording.py
```

They intentionally assert the inspected 0.18 behavior. Reassess on an image update;
passing these probes does not authorize or qualify the proposed recorder.

## Owner sequence and implementation experiments (September 14, ongoing)

The owner's 21:50–22:00 center-rock event was found in September 13 footage
(America/Chicago, CDT; Unix start 1789354200). The retained source has approximately
530 seconds of coverage within that ten-minute interval; gaps must remain gaps.
Twenty-five sampled frames yielded 23 draft visible-gecko boxes. The public
checkpoint localized **0/23** at IoU 0.5 in each of full-frame, 640-pixel-crop, and
256-pixel-crop trials. Grayscale/contrast preprocessing and a separate Grounding
DINO tiny experiment also failed to establish usable localization.

Local custom-training experiments have not yet qualified a detector:

- The first YOLO11n experiment recognized many rock poses but labeled the empty
  rock as a gecko at confidence 0.55157. Rejected checkpoint SHA-256:
  `a9329861c2032a87b904c0a771257432367263d87649b9173d93619f584edd18`.
- A second experiment added the gecko's departure onto the water dish and reviewed
  empty-rock negatives. Its selected checkpoint produced no detections at a 0.05
  diagnostic floor in 20 later branch-crop trials, including visible geckos.
  Rejected checkpoint SHA-256:
  `0cf88c8dde2db9aee1a114fd8a216dcfe01a10de8510a7bf935a1f4ea3e41175`.
- Later night footage supplies more poses on both branches and two simultaneous
  geckos. Further training uses 65 development images and 18 development validation
  images. A later curled-tail event and matching empty views are reserved for a
  separate challenge. Correlated frames from one night are not independent
  population-level accuracy evidence. The owner has no daytime photos available;
  daytime recognition remains unverified.

[gecko_recording_gate.py](../hosts/apps3/gecko_recording_gate.py) is an experimental,
unwired retention gate with 19 passing temporal-policy tests. It requires confirmed
current gecko tracks and actual subsequent observations; it never extrapolates a
future recording tail. It rejects whole segments crossing an accepted boundary,
which can omit edge footage. It does **not** establish model or movement accuracy.

An isolated replay uses the exact live Frigate image ID listed above. With synthetic
track metadata and a real 4.998278-second MP4, it retained segments at 100–104.998278
and 125–129.998278 within an accepted 100–130 interval; it rejected 98–102.998278,
129–133.998278, and 131–135.998278. All 150 decoded frames of each retained copy
matched the original. Stalled input was dropped, and patched startup/hour/offline
preview entrypoints attempted no imagery writes. These are media-path tests, not
an end-to-end gecko replay or a production deployment. Experimental patched source
and reports remain in the private temporary work directory.

A further movement probe exposed a separate blocker: the stock `gecko` label uses
default box-based movement thresholds, not its appearance classifier. A frozen
real gecko image with synthetic box jitter produced 73 native movement updates and
incorrectly authorized recording at 35–40 seconds. A pixel-based movement prototype
is being tested against jitter, background motion, camera movement, and actual
footage. The detector and movement path must both pass before enabling retention.

Further isolated experiments found and addressed additional integration gaps:

- The stock box-jitter probe produced 73 false movement updates. The experimental
  pixel classifier produced zero on the same probe and one update for a controlled
  pixel movement with an unchanged box. Camera translation, rotation, and unrelated
  background movement controls also passed. This does not establish real-motion
  recall across the enclosure.
- A separate one-class OpenVINO adapter matched raw PyTorch outputs on four
  development crops (box-coordinate error below 0.001 pixel). Its local inference
  timing is not a benchmark on `apps3`, and the exported model is unqualified.
- Frigate's remote detector defaults to a 0.4 score floor. A camera-specific replay
  patch passes the configured gecko association floor instead; other camera and
  mixed-label cases retain their original behavior.
- An inline JSON label-map key remained a string in Frigate's merged map, leaving
  integer class zero mapped to `person`. An explicit `0 gecko` label file corrected
  this in the complete replay. Configuration validation alone did not catch it.
- The motion-driven search missed the small gecko in the complete replay. An
  experimental overlapping scan now searches independently of motion and requires
  fresh inference for stationary gecko observations. Its geometry covers the full
  1080-by-1920 image with 50 regions, at most six extra inferences per frame.
- Boundary trimming preserved accepted portions of actual MP4s in component tests.
  The complete Frigate process exposed a fork-inherited thread-executor shutdown
  state; the experimental encoder now runs through an asynchronous subprocess.
  Complete isolated replay now passes with the subprocess encoder.

The fourth model's selected operating point passed the small development set but
missed five additional known branch poses. Wider scanning also exposed false
positives on reflections, plants, and enclosure edges. Subsequent training includes
reviewed hard negatives and adjacent climbing poses; no checkpoint is qualified.
Thirty-two daytime archive samples were inspected without finding a clear positive
gecko example. The newer live image used for negative mining is development data,
not an independent holdout. The original later curled-tail challenge was held out until the V9 evaluation
described below. All complete-pipeline replays use isolated local containers and synthetic
scene timing around real footage, not the production camera.

The live recorder retains its original general-motion policy.
No candidate model, recording patch, or detector configuration from these
experiments has been deployed. The requested gecko-only behavior is not confirmed.


The subsequent timestamp audit found that second-resolution recording filenames
could extend a nominal 30-second quiet interval by about 0.8 seconds. The
experimental capture path now preserves presentation timestamps through NUT video,
and matches recordings using FFmpeg's segment timestamp manifest. In a complete
Frigate replay, decoded frame counters matched observation and stored-recording
timestamps; a complete observed visit retained no empty-scene frames, no frames
before confirmation, and no frames beyond the quiet deadline. A later return
started recording again. Killing the fixture's capture process established a new
clock epoch and recovered through the watchdog. These are integration checks with
an unqualified model, not evidence of general recognition accuracy or deployment.

The retention gate additionally requires a strong current-frame score, because
Frigate keeps a track confirmed after later weak associations. Its 22 regression
cases pass, including rejection of those weak associations. The source patch is
packaged with exact original/result checksums and helper checksums; application,
idempotency, and refusal of modified source or helpers were verified on local
copies. The latest bundle passed another complete replay after correcting departure evidence across processing gaps.

The sixth recognition candidate localized the development poses at the association
threshold, but wider scanning found a high-confidence false positive on an opening
in an older daylight view. It was rejected before exposing the reserved challenge
set. A seventh candidate was trained with those reviewed opening examples.


With production motion settings, an isolated replay exposed a 1.2-second processing
gap that erased departure evidence and prevented recording on the next visit.
Spatial registration now survives a processing gap when the background still
matches; movement across the gap is suppressed. Both a dropout-without-departure
control and a departure-with-gap control pass. The subsequent complete V7 replay
passed the exact-timestamp, empty-scene, quiet-cutoff, and repeated-visit checks.
The model remains unqualified: its full scan detected 20 of 28 distinct development
boxes at the locked 0.5 recording threshold. Native scan crops from training
sources were added for the next experiment; validation and the reserved later
event were not added to training.

A bounded, isolated two-CPU benchmark on apps3 verified V7's ONNX/OpenVINO outputs
against four development reference inputs (maximum box difference below 0.00036
pixels; score difference below 0.000001). Median per-crop inference ranged from
23 to 43 ms. The benchmark container and its remote temporary inputs were removed;
production Frigate remained healthy. This measures numerical compatibility and
inference cost, not end-to-end production throughput or gecko recognition accuracy.


Further natural-video qualification exposed a recording-batch bug: the trim lock
persisted across separate asyncio.run event loops. The lock is now created within
each maintenance batch. Boundary encoding uses x264 ultrafast at CRF 16; a local
4.57-second clip took 4.61 seconds versus 8.99 with veryfast, with file size rising
from 5.34 MB to 12.10 MB. Entire accepted segments still use stream copy. A subsequent
natural descent replay retained 120.34 of 120.95 seconds authorized by independently
subscribed observations. The 0.62-second omission fit the per-window frame-boundary
allowance, with no persisted interval outside authorization. This validates the
retention path under that replay, not recognition of unobserved geckos.

The V8 experiment amplified false detections on the upper branch. Ambiguous upper
positive annotations were removed from V9 training and scored development data;
they were not relabeled as negatives. A V9 checkpoint found all 27 clear development
boxes with the complete overlapping scan and produced no primary detections in the
33-image wider background survey. It was frozen before the reserved later event:
checkpoint SHA256 e6d68296f4052b4ccdba4e7d514efd94f93b20577a31f4c1922a692ad8862f66,
recording threshold 0.5, association threshold 0.15. It then missed all three
reserved curled-tail examples, including with full scanning. It is rejected for
deployment. Those reserved results must not subsequently be presented as an
independent test of a model trained using them. Owner confirmation of the
curled-tail annotation was requested. Subsequent temporal archive review, described
below, established the identity independently.

No gecko model or recording changes have been deployed. The requested accurate
gecko-only production behavior remains unconfirmed.


The quiet deadline now belongs to the ongoing recording as well as individual
tracks. Discovering additional stationary geckos cannot repeatedly restart the
30-second interval; verified movement can extend it. Regression cases cover seven
staggered stationary discoveries, a later separate visit, and an observation gap.
A complete replay with seven static copies of an actual gecko passed two visits:
897 retained frames per visit, no frames before confirmation or outside presence,
and no overrun of the shared quiet deadline. During the steady visible portion,
63 processed frames had six fresh strong confirmed objects and 61 had seven. The
median processed-frame interval was 0.4 seconds. These are synthetic concurrency
and retention checks, not recognition of seven different animals.

Additional evening archive review found clear floor, lower-branch, and hide
climbing poses. V10 trained on the floor and lower-branch examples; two separate
hide visits remain reserved before inference (six positive frames and four
reviewed empty-region controls, with correlated adjacent frames within each visit).
V10 still missed the original curled challenge and introduced four table-region
false detections in the wider survey. It is not qualified.

Reviewing the 00:01:20--00:04:20 CDT sequence established the curled animal's
identity: a gecko visibly travels along the branch, turns downward, and curls its
tail into the previously ambiguous position. V11 includes five reviewed poses
from that sequence and the table false-positive crops. The exposed curled event
is now development data, never an independent validation set for V11. The two
hide events remain excluded by source-file checks. Training and evaluation are
still in progress; production remains unchanged and the goal is unconfirmed.

A live apps3 RTSP demux check found that the first segment's CSV origin preceded
its first packet by 1.1 seconds. The guard would have discarded that segment.
The clock helper now checks the MP4 stream offset and duration against the CSV,
then derives the actual start from CSV end minus stream duration to avoid the
MP4 edit list's millisecond rounding. Boundary trimming subtracts the stream's
local timestamp origin. In a subsequent 15-second live check, 72 detection frames
had monotonic timestamps at about 0.2-second intervals; the reconstructed first
segment start matched the first detection PTS within numerical precision. A
43-frame boundary clip stayed inside its authorized interval. The isolated
one-CPU test container and temporary remote inputs were removed; production
Frigate remained healthy. This verifies the live demux/clock/clip components,
not model recognition or the full production recording pipeline.

The complete local replay was repeated after the RTSP offset correction. Both
observed visits retained clips (892 and 893 frames), with no observation or
recording timestamp errors, no frames outside presence, no recording before
confirmation, and no quiet-deadline overrun. The selected model for this replay
was still the unqualified V7 checkpoint; this is final-clock integration evidence.

V11 detected 37 of 40 clear development boxes with full scanning, and was not
qualified. Re-saving dark training crops as JPEG changed some prediction scores
materially (for one centered crop, 0.406 on the original versus 0.639 on the
training JPEG), although misses also occurred on the training JPEG itself. V12
added reviewed adjacent curled poses and explicit fourfold training weight for
those crops; repeated crops are not independent examples.

The routine scan now covers only the reviewed enclosure, x=0..1080 and y=0..1200,
with 30 overlapping native regions and four extra regions per processed frame.
Motion and object masks exclude the table below y=1200. All reviewed positive
boxes fit fully within a scan region. A separate apps3 shadow Frigate, connected
to the existing restream through a private Unix socket, completed a two-minute
live run without stalls or reconnects and with no recordings or events in the
observed background scene. After startup, processing was mostly 4.7--5.1 fps,
with one 3.8 fps sample, versus 2.5--3.6 fps using the broader scan. Both temporary
containers were removed. A seven-copy replay also passed both quiet cutoffs;
all 130 sampled steady-scene frames had seven fresh strong confirmed objects.

A V12 epoch-10 snapshot was frozen at SHA256
6ea471db660b15e2d97bcad7d2b884484b42a315700eec61389691c4f3595b70,
with the same 0.5 primary threshold and 0.15 association floor. It detected all
46 clear development boxes, the three exposed curled examples, and no primary
objects in the 33-image background survey. It then failed the reserved hide test:
zero of six target geckos across two hide-climbing visits were detected. The four
empty-region controls and four fresh background frames had no primary detections.
The six hide frames are now an exposed development challenge, not an independent
holdout for subsequent selection. The checkpoint is rejected for deployment.

The gate now treats a tightly contained torso box as the same location as the
whole-body box, within a bounded area ratio. Such localization changes were
observed in development predictions and must not restart a quiet deadline.
The resulting 23 temporal regression cases pass. General recognition and
gecko-only production recording remain unconfirmed; production is unchanged.

The revised V13 dataset reconstructs source crops as PNG, adds the exposed hide
examples, includes the native enclosure scan contexts, and trains with wider
rotation. It contains 536 unique annotations, 647 weighted training crops, and
23 development validation crops. An annotation audit found no conflicting labels
for identical source/crop pairs and no out-of-bounds boxes. A local SAM2 masking
trial included substantial background in several proposed animal masks; none of
those masks were used for training.

The V13 epoch-10 checkpoint detects the exposed hide examples but still misses
three of 55 scored development boxes and produces five primary predictions in
two older daylight frames. It is not qualified. A later plant-climbing sequence
remains untouched by detector inference and training. It is about six minutes
after the exposed right-hide frames and may show the same animal and visit;
therefore it tests new poses, not independent animal identity.

The complete plant replay contains 6,750 decoded frames over about 225 seconds.
It preserves nominal archive segment origins and explicitly represents the missing
75--80 second interval as 150 black frames. Those frames are missing observations,
not evidence of an empty enclosure. All decoded PTS are monotonic, with a maximum
frame interval of 0.03506 seconds. This prevents silent removal of the archive gap
from the quiet-cutoff test.

The completed V14 native-orientation pass (checkpoint SHA256
be53597bf1d6cb4381ca7c9487313fa793462936d4164dd0c96656909ccf610f)
matched 54 of 55 development boxes at score >=0.5 and IoU >=0.5, with no
primary detections in the 33 reviewed background images. The remaining floor
example had strong partial-body detections but its whole-body match scored
0.445; the scoring criterion was not relaxed. A hide-doorway false detection in
an older positive frame also prevents qualification. V15 adds only visually
reviewed doorway negatives and increases the weight of the existing reviewed
floor example. The reserved plant sequence and four fresh background images
remain excluded from training and inference at this point.

The experimental recording worker now writes an atomic monotonic heartbeat only
after completing a maintenance pass. A separate health wrapper preserves the
existing camera/keyframe checks and fails on a missing, malformed, future, or
more-than-120-second-old heartbeat. This addresses the observed failure mode in
which recording maintenance stalled while capture and the API remained alive;
it does not substitute for checking detector accuracy or clip contents. The
helper's success and refusal cases pass; full patched runtime verification is
still required. No production health check or recording configuration changed.

The full seven-copy replay with the 23-case gate and recording-worker heartbeat
passed both complete visits, retaining 898 frames each. The decoded frame-counter
checks found no recording before confirmation, outside presence, or after the
quiet deadline, and no observation/recording clock errors. The heartbeat remained
fresh after recording maintenance. This used the earlier rock-capable V7 model
and synthetic copies of one animal, so it verifies the current recording policy
and worker integration, not recognition of seven distinct geckos.

V15 (SHA256 fca2ddcb6c8c862e171c8213d476a0c9a1f4a2c1c452e019471f2693f26fa158)
passed all 55 exposed development boxes and produced no detections in the 33
reviewed background frames or the known doorway false-positive region. It was
frozen before reserved evaluation. It then failed all three plant whole-body
matches: one partial animal scored 0.655, while the other two target poses were
missed. Four fresh background frames had no primary detections. The independent
54-image later-night survey produced seven detections, all visually reviewed as
lamp reflections. V15 is rejected, and these tests are now exposed challenges.
Its ONNX SHA256 is
6ae3bff936f765d08cff9b8456787b9ba4c9793eff1d6db94a1a9b58b9466550;
actual apps3 numerical parity passed on four inputs, with median inference about
21--23 ms. Numerical compatibility does not reverse the recognition failure.

V16 broadens the training material using CC0 photos from research-grade
[iNaturalist H. turcicus observations](https://www.inaturalist.org/taxa/34435).
The private provenance manifest preserves each photo's source, attribution,
license, and checksum. Of 60 downloaded observations, 41 reviewed visible-animal
photos enter training, ten are reserved before model inference, and nine unclear,
severely occluded, blurry, or visibly dead examples are excluded. Visible-animal
boxes were manually reviewed on normalized images. Color and scale variants add
both ordinary lighting and synthetic red-light examples; they do not constitute
real enclosure daylight validation. The dataset has 974 training images,
including the existing enclosure examples and exposed lamp negatives. The plant
sequence still does not enter training. No enclosure images were uploaded to an
external service. A separate public dataset named GECKO was excluded after its
example image showed a toy.

The current patched recorder also passed a full synthetic positive replay on
apps3 itself, limited to four CPUs and 2.5 GiB. Both complete visits retained
892 frames with no pre-confirmation footage, outside-presence frames, quiet
cutoff overrun, or clock mismatch. All 96 sampled steady-scene observations had
seven fresh strong confirmed tracks. Sampled memory was approximately
0.9--1.1 GiB and CPU use approximately 2.0--3.5 cores; the worker heartbeat was
fresh and production Frigate remained healthy at every sample. The private test
container was removed. This uses the rejected V15 model and seven copies of one
gecko, so it qualifies recorder throughput and integration, not model accuracy.

An additional archive survey selected 36 frames using lower-enclosure motion
peaks, without running the gecko detector. Eight clear target poses were then
annotated and reserved before detector inference: branch traversal/hanging,
rock climbing, and hide/plant movement. The source frames were collected after
V16 training began, and their absence from training was verified along with the
ten public observations and the exposed plant sequence. Nearby frames may show
the same animals and events; this does not establish independent animal identity.
Other partially occluded animals in these frames are not labeled as background.

V16 (SHA256 97e2f58821b2651c82fc413692e1dc6ff4b30c9b9c9c77de60083b213cea3870)
matched 54/55 development boxes, with no primary detections in either the
33-image background survey or the now-exposed 54-image later-night survey. It
detected the previously missed horizontal plant pose at score 0.779, but still
missed the other two plant poses and regressed on one older branch pose.
Increasing inference size to 416 and applying grayscale/local-contrast
preprocessing did not resolve those failures; neither change was adopted.
The new reserved enclosure and public-photo tests remain untouched.

V17 retains the species-diverse corpus, reweights the branch regression, and adds
nine manually reviewed poses from an earlier right-plant traversal. It has
1,137 training images. The existing augmented PNG/label pairs were preserved
rather than reconstructed from raw sources, and all reserved-source exclusions
were checked again. The later exposed plant sequence remains absent from
training. There is still no production gecko model or gecko-only deployment.

A separate real two-gecko archive sequence is prepared for tracking replay:
9,450 decoded frames over 315 seconds, with monotonic timestamps, a maximum
frame interval of 0.035056 seconds, and no missing archive intervals. It includes
two of the reserved target frames and has not been run through a candidate yet.
Four fresh morning snapshots were reviewed before inference and reserved as
visible-background controls. Neither collection establishes daytime positive
accuracy or confirms animals hidden behind enclosure furnishings.

V17 (SHA256 adfc7b542a5b55dbd63dbc74c6df16c52a9da9ce0fee510817d98cec2b49778e)
matched all 55 older development targets but still missed two exposed plant
poses. Four daytime false detections were reviewed as lamp/human reflections.
Two overlapping detections in the later-night survey were a real gecko, not
background: adjacent five-second archive frames show it emerging from the
right plant, turning, and climbing onto the hide. This discovery was reviewed
after inference and is not an independent validation result.

V18 is training on 1,289 images, adding the three already-exposed plant poses
and the four reviewed reflection crops. The later-night discovery remains
outside training. The reserved two-gecko sequence now has thirteen manually
reviewed target boxes in nine frames, in addition to the eight reserved motion
targets. No training source falls within that two-gecko sequence's time range.
These are correlated observations, and partially occluded animals outside the
selected boxes are not labeled as empty. All reserved detector tests remain
untouched while the known development failures are addressed.

V18 (SHA256 ad011af287a20b52f7f7e60bf6748616078cf9e47241fbb4308b2a8afb1c384d)
matched all 55 older targets and all three exposed plant poses (scores 0.916,
0.866, and 0.907). It also detected the later-night gecko discovery without
training on that frame. Thirteen false detections remained in daytime images,
principally the upper branch itself; these were visually reviewed. V19 expands
negative training to all 930 native scan regions from the 31 reviewed daytime
frames, weighting the failing regions. It has 2,310 training images and is not
yet qualified. Reserved targets and fresh backgrounds remain outside training.

The current helper bundle also writes a detector heartbeat after completed
inference, at most once every five seconds. The health wrapper requires it to
be no more than 30 seconds old when detection is enabled. Recording-worker
liveness remains a separate check. Missing, malformed, nonfinite, future, and
stale heartbeat cases were rejected. A complete local seven-copy replay with
the updated bundle retained 898 and 897 frames for two visits, with no clock,
presence, confirmation, or quiet-window violations and both heartbeats fresh.
That uses the unqualified rock fixture model; the new heartbeat bundle still
requires the selected-model apps3 replay before deployment.

Private Nix/YAML runtime templates are prepared, with the model checksum
deliberately unresolved. Their schema was validated inside the exact patched
Frigate image using fixture model/label paths. Native named-mask objects avoid
depending on startup migration of legacy mask strings. This does not qualify
the detector or enable production recording.

The base apps3 build exposed an unrelated Tuwunel downgrade from the running
1.9.1 to the checkout's 1.9.0. Aligning that single image version with the running
service restores the exact existing apps3 system closure
`71svz13l78qg1j7qb6ps96q5hqgr2f9d-nixos-system-apps3-26.05.20260911.21a67dc`.
No host deployment has occurred.

V19 passed the exposed enclosure checks but failed its first reserved test:
7/21 target boxes matched and two fresh background frames triggered on the
door latch. The public-photo test had 43 true positives, 15 false positives,
and 17 misses across 60 correlated renderings of ten observations. Those tests
are now exposed development data; their original failed results are preserved.

V20 (SHA256 62f06a1423a07eaac3ceb0f957f53d24f0cebd66739ca8980693b6b5278d7758)
used 2,782 training images, adding exposed hanging, floor, and plant poses with
all annotated animals labeled in each crop. It matched all 55 older targets,
all three exposed plant targets, and all 21 previously reserved targets. The
latch false detections disappeared. It nevertheless failed: four detections
in the older background survey and six in the later-night survey were reviewed
as branch texture, and the later plant discovery scored only 0.400. V21 adds
those reviewed branch negatives and repeats existing earlier plant examples.
Neither model is qualified for production.

The next reserved test contains nine selected targets in eight frames and four
fresh, visually reviewed background frames. The continuous validation archive
spans 325 seconds without any positive training source in its time range.
Its missing five-second archive interval is represented explicitly as black
frames and must retain no footage; it is unknown source data, not proof of
animal absence. Four annotated targets in that video remain untouched by
detector inference while the known regressions are addressed. No daylight
positive accuracy or recognition of seven distinct individuals is established.

The private runtime template also passed an apps3 NixOS toplevel build with a
placeholder checksum and the existing secret overlay. Comparing its units with
the running system showed only Frigate and the generated container updater
changing; the latter contains the pinned Frigate image and an equivalent skip
list. This build must never be activated: it deliberately has no qualified
model. The final selected-model build and deployment remain outstanding.

V21 used 3,172 training images. Its fourth-epoch checkpoint removed the older
background failures but missed the later plant pose and triggered on hair and
branch texture. The final checkpoint improved that pose but triggered on plant
leaves. A separate candidate averaged 75% of the fourth-epoch parameters and
floating buffers with 25% of V19. This experiment follows the general
[weight averaging approach](https://proceedings.mlr.press/v162/wortsman22a.html);
it does not assume the paper's results transfer to this detector.

The averaged checkpoint (SHA256
0fe8300045ac9d6195ef398c82099c1498332794cd900d44d98e41f5fc3cd878)
passed every exposed pose and background check, including four new direct-sun
snapshots. Its first reserved V3 test nevertheless failed: 3/9 targets met the
unchanged score and IoU requirements. Three geckos were missed and three had
strong detections with insufficient localization overlap. None of the four
reserved backgrounds triggered. The final V21 checkpoint subsequently matched
5/9 on these now-exposed targets; that is development evidence only.

V22 adds the exposed V3 poses and reviewed hair/branch negatives. The V3 video
is consequently development footage, not an independent event. Its 22 further
reviewed branch-presence frames remain useful temporal checks but cannot undo
that training overlap. A new 02:19 plant sequence has no training frames: it
contains a gecko emerging and turning, followed by exposed leaves. Temporal
review corrected an initial mistaken assessment of a detection at 02:19:00;
the nearby animal does not validate the exact empty-leaf frame. That frame was
excluded from V22 training pending review and remains a negative control.

The 04:45--07:45 archive survey supplied 42 additional lower-enclosure views,
without a clear positive in the reviewed area. It does not establish daylight
positive accuracy or absence of animals outside the reviewed area. No gecko
configuration or model has been deployed.

V22's final checkpoint (SHA256
af2ebd8d0b27fd9b68fbeecba56b9d22347d0d8b826a6c68a31c8701fcfdf35d)
matched all nine exposed V3 targets and had no strong detections in the tested
background controls. The remaining development failure was the 04:39 partial
head, scoring 0.301. Exact-frame review confirmed that this case contains a
small visible head, neck, and forelimbs; it is distinct from the empty 02:19
leaf frame. V23 adds four reviewed partial-head examples from the already
exposed 04:39 event, using 3,828 training images. The old evaluation boxes and
failed results remain unchanged.

The separate 02:17--02:21 video contains 6,450 frames over 215 seconds, with no
missing archive intervals. Six visible-gecko portions and four empty-scene
frames were annotated before V23 inference. Native coordinate grids corrected
the draft boxes before freezing them; these data never entered training.
Replay qualification additionally checks that no video was retained at the
reviewed empty source times, independently of the gate's own observations.

V23's final checkpoint matched the known positive targets but produced four
strong background detections on plant, hide, and branch texture. Its first
checkpoint also triggered on a branch. Two additional raw first-checkpoint
boxes belong to the already annotated real 04:39 gecko and overlap its stronger
box; they are duplicate partial detections, not evidence of a background false
positive. The original reports are preserved. V24 adds the five visually
reviewed false-positive regions as 160 negative samples. The reserved 02:19
sequence remains unused. Production Frigate was checked healthy before this
training run; its general-motion recording configuration is still active.

V24 reinforced five negative crops, using 3,988 training images. Its first
checkpoint still triggered on internally clipped plant texture and missed the
known floor target at natural-dual-review/305.png. The final checkpoint removed
the strong background detections but still missed that floor target (0.462).
Neither checkpoint qualified.

The detector now experimentally requires two pixels of context at internal
crop boundaries, preserving actual camera-frame edges. Overlapping regions
provide other views of boundary-crossing animals. This addresses strong texture
predictions truncated by a tile, without changing confidence or localization
requirements. Three focused context tests were added; all 26 tests passed.
The first context experiment's floor miss was already present in V24's first
checkpoint, not caused by the context rule. A centered-recrop experiment did
not resolve that existing miss and was not added to the runtime.

V23 final with the context rule passed every exposed pose and background check,
but its first reserved V4 test failed: 3/6 targets matched and 0/4 backgrounds
triggered. Two poses were missed and one strong detection had insufficient box
overlap. The original frozen manifest and failed result remain unchanged. V25
adds the now-exposed V4 positives, same-view empty controls, and the known floor
pose to V23's data, giving 4,356 training images. The 02:19 video is now
explicitly development footage and cannot count as independent validation.
No model export, selected-model replay, or production gecko deployment followed
this failure.

A further archive survey selected 36 frames using motion heatmaps, excluding
the two plant events now used in training. Adjacent frames confirmed a separate
gecko crossing the hide around 01:36 and disappearing behind the plant. Six
poses and four full-scene empty controls were reviewed before detector inference
and frozen as V5. The continuous archive contains 4,650 frames over 155 seconds,
with no gaps or synthetic black frames. Its interval has no V25 training source;
a previously used upper lamp-negative crop at 01:35:00 precedes the video.
Motion blur makes exact contours less distinct, and the samples are correlated
poses of an unknown individual, not a daylight or seven-identity qualification.

V25 final (SHA256
389c56bd48a3fd63d81ba0968090f11bfe78bcb6d6c596397ce383d97ab3f8e4)
passed the older positive targets and 5/6 exposed V4 targets. It failed on one
branch background and the first thin plant pose. Comparing that pose against
the original empty and adjacent frames supported preserving its annotation:
the model's box includes adjacent leaves. Its original localization requirement
was not relaxed. V26 adds 120 copies of that unchanged image/label pairing and
48 copies of two reviewed branch negatives, using 4,524 training images. The
reserved V5 hide sequence remains excluded from training and inference.


V26 final (SHA256
57c6c25930031712da449eb35ca8a18c847f937ae85335fc2fbae3c50ba96ae7)
passed all exposed development checks, then failed its first V5 test: four of
six hide-crossing targets matched; none of four reviewed backgrounds triggered.
The curled pose was missed and the following pose was poorly localized. The
original frozen annotations and failure remain preserved. V27 adds this exposed
crossing and matched empty-hide crops, using 4,884 training images. That event
is now development data, not independent qualification.

V27 final (SHA256
9efec2a7403bdb99e5c81ce65c32056edf659c919205f4289b941d1ddd702471)
failed development: 5/6 exposed hide poses matched and two overlapping detections
triggered on one background branch. All 55 older targets and the exposed plant,
floor, and partial-head targets matched. It was not exported or deployed.
Earlier saved checkpoints trade the thin plant pose against a blurred hide pose;
those results are also preserved. No confidence or IoU requirement was relaxed.

Six additional hide-crossing frames were manually annotated before inference,
along with four fresh daylight main-enclosure backgrounds. These are temporal
checks from a represented event, not independent animal or event qualification.
The separate containers below the main enclosure remain outside detection scope.
A proposed stationary branch replay contains 55 seconds of missing archive in
its 135-second timeline. Those intervals are explicit gaps, not negative examples
or evidence of gecko inactivity. The first 65 seconds are uninterrupted; the
branch identity is being rechecked before using it as stationary ground truth.
The old ambiguous upper-branch positive labels remain excluded from the current
training set. Production Frigate remains healthy with general-motion recording;
accurate gecko-only production behavior is still unconfirmed.


The fixed midpoint of V27's first two checkpoints (SHA256
6e9bffa8509f63f76b80aa9e6b683d434f97ab0e938a78ef8cddbadbfa2ee943)
passed the complete exposed development suite, then failed the frozen V6
temporal test: 4/6 boxes matched and 0/4 fresh daylight backgrounds triggered.
The two failures had strong gecko predictions but insufficient localization
against the unchanged manual boxes. V28 adds these six exposed poses and matched
empty-hide crops, giving 5,316 training images. The original V6 failure remains
preserved; those frames are no longer independent validation.

A local component diagnostic deliberately used the rejected V27 midpoint with
the current context-rule patch; it is not deployment qualification. In the
155-second real hide-crossing replay, 7/12 annotated poses matched the actual
fresh tracker output. All four reviewed empty-time controls passed. Retention
contained 59.8667 of 60.3999 authorized seconds, with the 0.5332-second omission
inside the frame-boundary allowance and no recording-timing errors. This
reproduced localization failures in the real runtime while exercising the new
source patch. The diagnostic container was removed. Separately, the current
bundle passed exact-image preflight, application, idempotence, and refusal of
unexpected source changes; its manifest SHA256 is
87e03352bb3a9e98bb72576c8c01f94ade15780e8f90726d317eed22814ecf0f.


An uninterrupted 75-second archive from the owner-confirmed rock sequence
contains a long still pose followed by a head turn. Review covered 5-second
samples and the ten lowest-correlation pre-50-second frames selected from all
375 frames sampled at 5 fps, using a fixed human ROI and background registration.
A component test supplied the human-confirmed gecko identity/box to the current
motion helper and retention gate. It produced exactly [0,30] seconds during the
still period, no early movement flags, and restarted at 53.7987 seconds on the
visible head turn. This is real-noise movement/quiet-deadline evidence, not
selected-detector or end-to-end persisted-recording qualification.


Further localization refinement did not qualify V28: its final checkpoint
matched 5/6 V4 and 5/6 V6 targets. V29's first checkpoint passed all exposed
cases, then matched 5/6 reserved V7 targets, missing one motion-blurred hide
crossing. The final V29 checkpoint detected that exposed blur but falsely
identified a foreground person in another frame. Both failures are preserved.
V30 starts from the first V29 checkpoint and adds the now-exposed V7 examples
and foreground obstruction negatives. Its first checkpoint, SHA256
33242223282fe098cff6334e1ebe6748671f4181ff6a65df13d9fff9ac44bb17,
passed all exposed development cases, including all six V7 targets and zero
strong detections on their four daylight controls. Six new temporal branch/floor
boxes from the represented two-gecko event and four new background controls
were reviewed and frozen before V8 inference. Both floating and runtime integer
boxes must meet IoU 0.5 at confidence 0.5. These correlated temporal tests do not
establish independent-event, individual-identity, or daylight-positive recall.

The current bundle manifest SHA256 is
df16ff6c55ceeb6f9f4993eafb928a608513723f0124ea0bd470342ee950ce97.
Changes since the preceding context-rule verification only clarify experimental
status and helper documentation. Exact-image patch preflight, application,
idempotence, and refusal were repeated successfully for this manifest.
Production gecko tracking remains unconfirmed and the live configuration has
not yet been changed.


V30's first checkpoint failed the frozen V8 test on one floor-gecko box (5/6,
zero background false detections); predictions included the animal but exceeded
the localization tolerance. The final checkpoint, SHA256
8a0c0180d59db9566ba3208dc05708e751ab1b660b87022cb4e4e6d4e2d2fba9,
passed the exposed suite and all six V8 boxes, including integer-box checks,
with zero detections on the four new backgrounds. V8 is now exposed to checkpoint
selection. A V31 dataset was prepared but no V31 training was started. The final
V30 ONNX SHA256 is
ad794b579a7251df5f49394d32163baeefaf36bace0dcfc055f9cbbd236047a7.
Its actual-apps3 numerical comparison passed all 300 raw cases (median 27.62 ms,
p95 47.41 ms). This establishes adapter parity, not recording qualification.

A separate local diagnostic used the rejected first V30 checkpoint on the real
75-second stationary-rock video. It matched all observed steady frames, first
confirmed the animal at 1.799 seconds, retained 29.733 seconds of the initial
visit, retained zero forbidden quiet-period footage, and restarted after the
head turn. Actual persisted packets passed the timing checks. This is useful
current-patch evidence but the final selected checkpoint must pass its own
replay. An isolated final-model NixOS candidate built successfully; only the
Frigate and container-updater units differ from the currently running closure.
It has not been activated.


The first selected-model continuous replays failed and blocked deployment.
The synthetic background sequence generated a strong false detection over the
lamp from a 2,424-pixel generic motion region resized to the model input. The
still-image suite had only exercised native 320-pixel crops. The hide replay
matched 14/15 targets and narrowly exceeded its omission allowance; the plant
replay matched 3/6 and dropped about 21 seconds of authorized recording after
an encoder/cache backlog. These failed reports remain preserved.

The gecko-specific runtime now discards generic-scale inference regions and
uses the existing 30 native grid crops exclusively: two overlapping crops per
track plus the rotating discovery scan. Other object types retain their original
region behavior. This aligns runtime image scale with model qualification and
prevents global motion from shrinking enclosure fixtures into untested shapes.
Twenty-nine policy/crop tests pass, including oversized-region refusal by
construction, continued stationary discovery, and overlapping track views.
The new bundle SHA256 is
c417fad18b5ed44adb4ebbebec9001eada90dcf069e03db9b409d1b063cdd7e2;
exact-image patch preflight/application/idempotence/refusal passed. The model
itself is unchanged. Repeated apps3 numerical comparison passed 300 cases,
median 25.51 ms and p95 44.18 ms. Fresh runtime tests are required; no deployment
or corrected-runtime success is claimed from these component results.
