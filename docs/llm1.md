# llm1 LLM Service (Swift 1.5 Qwen3.8-Flash-Next)

`hosts/llm1/llm.nix` serves [SC117 Swift 1.5 Qwen3.8-Flash-Next GSQ-RCO
abliterated](https://huggingface.co/SC117/Swift-1.5-Qwen3.8-Flash-Next-GSQ-RCO-abliterated-GGUF)
(IQ3_S, 83,549,259,040 bytes in two GGUF shards) on llm1 (VM 210 on hv1, `10.1.11.9`, mesh
`10.255.0.9`) with [Strata](https://github.com/Niko1221/Strata) on the
passed-through GTX 1070. `strata.service` starts at boot and listens on
`127.0.0.1:8080`. Until 2026-10-06 it ran on devenv.

## Endpoints

| Client location | Base URL | Notes |
|-----------------|----------|-------|
| LAN / VPN | `https://llm.in.reinitialized.net/v1` (web UI at `/`) | rp1, ACME TLS, `internalOnly`; no key needed (see Web UI) |
| Mesh hosts | `http://10.255.0.9:1045/v1` | `llm-api-mesh.socket` forwards to loopback; WireGuard-encrypted |
| llm1 itself | `http://127.0.0.1:8080/v1` | |

On the mesh and on llm1 itself, every route except `/health` requires
`Authorization: Bearer <key>` (Strata also accepts `x-api-key`). The model ID is
`swift-1.5-qwen3.8-flash-next`; Strata answers to any model name. Strata also serves the
Anthropic Messages API (`/v1/messages`) and the Responses API (`/v1/responses`).

```python
from openai import OpenAI
client = OpenAI(base_url="https://llm.in.reinitialized.net/v1", api_key="<key>")
r = client.chat.completions.create(
    model="swift-1.5-qwen3.8-flash-next",
    messages=[{"role": "user", "content": "Hello"}],
    reasoning_effort="low",
)
print(r.choices[0].message.content)  # reasoning is in message.reasoning_content
```

The context is 131072 tokens, with two concurrent requests; a third waits.
The earlier Orca IQ4_XS deployment with Strata 0.1.44.1 and exact engine optimizations reached 40.6
tokens/s solo, 39.1 tokens/s total for two requests and 132.6 prompt tokens/s
on a fresh 1,580-token prompt in the pre-deployment live comparison
(2026-10-15). Live throughput was essentially unchanged from the freshly
restarted baseline; measured gains are in isolated CPU and dense-weight
preparation components. These are short samples; the
Performance section retains the broader earlier measurements and long-context limits.
Budget several minutes to read a fresh 30k-token prompt. Use `stream=True` for long prompts: Strata sends an SSE
comment every 10 s while it reads, and the proxy inactivity timeout is 1 h.
Follow-up turns reuse checkpoints of the conversation (6 by default), and each
of the two batch slots keeps its last conversation.

## Reasoning effort

Strata takes `reasoning_effort` `none`, `low`, `medium`, or `high` (the default),
also as `reasoning.effort` or `chat_template_kwargs: {"enable_thinking": false}`.
Anthropic requests use `output_config.effort` or `thinking`.

## Web UI

Strata's web UI is served at `https://llm.in.reinitialized.net/` (re-enabled
2026-10-12; it was removed on 2026-10-06 while llm1 was API-only). Internal
clients need no key there or on the API: rp1 replaces the request's
`Authorization` header with one of llm1's keys, read from the nginx snippet
`/var/lib/service-secrets/llm-lan-auth.conf` on rp1 (`secrets.llmLanKey`,
root:nginx `0640`, one line: `set $llm_lan_auth "Bearer <key>";`). Without
that file rp1 still starts and sends no key, so Strata answers 401. Mesh
clients (`10.255.0.9:1045`) still need their own key.

The configuration connects Strata to `strata-web.service` over loopback MCP
(`127.0.0.1:8091`). The web chat's **Use tools from MCP servers** switch enables:

- `web__search`: live SearXNG search with optional day/week/month/year filters,
  source URLs, snippets, and explicit upstream engine errors.
- `web__read_page`: public HTML/text/JSON pages with numbered text, links, and
  continuation offsets for long pages.
- `web__find_in_page`: text matches with line numbers and nearby context.

The Monitor tab lists three tools from `web` and one from `analysis`. API clients retain their
own tools unless they explicitly send `"strata_mcp": true`. The public UI origin
is explicitly trusted for upstream's same-origin MCP checks. The tool loop is
limited to 12 rounds, 90 seconds per call, and 24,000 result characters.

Search uses the existing SearXNG instance at `10.255.0.5:1029`; its JSON API
must remain enabled. Search-engine outages are returned to the model, not
silently presented as successful searches. Read source pages and cite their
URLs when answering research questions. Retrieved content is untrusted data.

The web service runs as a separate dynamic user without the model service's
API credentials, model state, or GPU access. Strata retains its loopback-only
network restriction. Public page fetches validate all resolved addresses and
connect to a validated address, rechecking every redirect; private, loopback,
link-local and non-HTTP destinations are refused. Only the fixed search backend
can receive private-network requests. Fetches have a 2 MB limit and socket
timeouts. No shell, filesystem, or write tools are exposed.

### Workspace and analysis

The local harness overlay (`hosts/llm1/harness/`) adds:

- **Chats & projects**: persistent conversation history, full-text search, project
  labels, and deletion. **Instructions** adds per-chat system instructions.
  New chats retain those instructions; project labels group conversations but
  do not implicitly share their attachments or instructions.
- **Edit & branch / Retry in new branch** preserves the original conversation.
- **Backup chat / Import chat** transfers a JSON backup. Imports restore text
  and file attachments; tool execution records and image payloads are not replayed.
- Attach **PDF, DOCX, XLSX**, or the upstream text/code/CSV formats. Documents
  are parsed in the isolated worker (8 MB input, 200 PDF pages, 200,000 extracted
  characters; spreadsheets read up to 20 sheets, 10,000 rows and 100 columns).
  Excel uses cached cell values; it does not execute formulas or macros.
  Scanned PDFs need OCR, which is not enabled.
- **`analysis__python`**: calculations, pandas/numpy analysis, matplotlib charts,
  and file creation (including DOCX/XLSX). Each call has a fresh workspace;
  the model must pass needed text data in `files`. Results include exit status,
  bounded output, and download buttons. Downloads expire after 24 hours and are
  served as attachments behind the existing API authentication. Generated files
  are limited to ten per call, 8 MB each. Tools must be enabled in chat settings.
- Fenced code has **Download**; HTML/SVG also has a sandboxed static **Preview**.
  Preview scripts, forms, and network loading are disabled.

Conversations and attachment text live in IndexedDB in the current browser,
not a server account. The old single chat is migrated on first use. Export a
backup before clearing browser data; storage failures are shown explicitly.
Other browsers/devices do not synchronize automatically. The server retains
only generated analysis downloads in `/var/lib/private/strata-analysis`, with
expired files cleaned on the next analysis request. This directory contains
user data; do not expose it or include it in source snapshots. The existing
model state, packs and backups are unchanged; rollback leaves the new browser
store and generated-file directory intact.

`strata-analysis.service` is a separate dynamic user with no credentials,
model mounts, or GPU. It uses bubblewrap with new user/mount/PID/network
namespaces, read-only Nix store, and a disposable working directory. Jobs cannot
see the host home, service secrets, other jobs, or stored artifacts. They have
no network, a 30-second wall timeout, 25-second CPU limit, bounded stdout, and
an 8 MB per-file limit. `/proc` is deliberately not mounted: the service's
systemd proc protections prevent an unprivileged nested proc mount, and these
analysis libraries do not require one. The service allows two concurrent jobs and is capped at
2 GB RAM, 64 tasks, two CPUs and 256 MB temporary storage. Python/package
installation and shell access to the host are not provided. The Strata process
continues to have loopback-only network access and its original credentials.

The UI/server overlay is built separately from the pinned CUDA engine. Its
installer checks exact integration points so an incompatible upstream upgrade
fails the build. Package tests cover upstream authentication plus authentication
and same-origin checks on the document/download routes.

This is **not full ChatGPT/Claude feature parity**. The comparison baseline is
[ChatGPT capabilities](https://help.openai.com/en/articles/9260256-chatgpt-capabilities-overview)
and [Claude artifacts](https://support.claude.com/en/articles/17153992-what-are-artifacts-and-how-do-i-use-them).
The configured model remains text-only: vision, voice, image/video generation,
authenticated/JavaScript browser automation, cross-device accounts, shared
project knowledge, autonomous scheduled tasks, connectors, and collaborative
canvas editing are not implemented. Static previews are not interactive apps.
Harness features do not establish frontier-model reasoning or tool-use quality.

Validate with `python3 tests/test-strata-web.py`, the llm1 host check, and
`tests/test-strata-analysis.py` with the service's `ANALYSIS_PYTHON`,
`ANALYSIS_BWRAP`, and `ANALYSIS_PRLIMIT` environment. The analysis tests execute
real sandbox jobs (calculation/chart creation, document extraction, isolation,
errors, and traversal). `tests/test-strata-workspace.cjs` uses Playwright and
`STRATA_WEB_ROOT` pointing at the built harness's `share/strata/serve/web`;
optional `PLAYWRIGHT_MODULE` and `CHROMIUM_EXECUTABLE` select local runners.
It tests attachment persistence, history/search, branching, instructions and
preview isolation with a mock API.

After deploying llm1, explicitly restart `strata` (its unit intentionally has
`restartIfChanged = false`). Verify four tools in Monitor (three from `web`,
one from `analysis`), a chat that searches/reads/cites a source, a Python-backed
calculation and artifact download, and a document upload. Source checks alone
do not prove that live chat path or model tool-selection quality.

Validated and deployed on 2026-10-14: the secret-free llm1 build, external-secret
build/activation, 26 upstream/route authentication tests, seven web-tool tests,
five real sandbox tests, and an actual 30-second timeout passed. Playwright
verified attachment persistence, history/search, instructions, branching and
static preview isolation against the packaged UI. Against the deployed UI it
uploaded/extracted a DOCX, observed the model execute Python for `6 * 7`, and
downloaded `answer.txt` containing `42`. A separate live streamed chat invoked
search and page reading and cited the IANA source. The deployed systemd worker
also refused access to the model's loopback port and host credential/state
paths. These are focused functional checks, not a comprehensive model-quality
or adversarial sandbox evaluation.

## API keys

Keys live in `/var/lib/service-secrets/llm-api-keys` (root, `0600`), one per
line, and `#` lines are comments. Override the path with
`secrets.llmApi.file` in the external llm1 secret module. Strata reads the
file through `LoadCredential`, so restart it after an edit
(`sudo systemctl restart strata`). Use one key per consuming project so a key
can be revoked on its own; `rp1 web UI (LAN)` is rp1's. With no key file, or
no key in it, the unit fails closed. The unit joins the lines with commas for
Strata (0.1.40+ takes several keys that way), so a key must not contain a
comma. The package build runs Strata's security tests.

## GTX 1070

The GPU (hv1 `0000:82:00`) sits in an R730 slot on CPU2 (NUMA node 1), where
llm1's vCPUs and memory are bound, and is passed through to VM 210. The guest
link trains at PCIe 3.0 x16 (Strata measures 12.5 GB/s host to device).
`llm.nix` loads the closed 580 driver, held at 580.173.02 (see "Update
policy"): the 580 branch is the last with Pascal, and the open kernel module
does not support it. CUDA 13 dropped Pascal, so everything is built with
`cudaPackages_12_9` for `sm_61` only. On hv1, nouveau takes the card at host
boot and Proxmox rebinds it to vfio-pci when VM 210 starts.

## Strata

`hosts/llm1/strata.nix` builds upstream's experimental CUDA 12 engine
(`STRATA_EXPERIMENTAL_SM60`, sm_61), with ggml from the llama.cpp commit Strata
pins and `-march=broadwell`. It also installs the Python server
(`strata-server`) and a Python for the packing tools (`strata-python`). A 12 GB
card is upstream's floor for supported cards; 8 GB Pascal is a community path.

### Current model preparation

The Swift artifacts are pinned to Hugging Face revision
`2b89cf3f7f2d9cb84275439e2c0cda83db15d32f`. The IQ3_S files are at the
repository root; both shards are required. Put them in
`/mnt/data/models/swift-1.5/`:

| File | SHA-256 |
|------|---------|
| `Swift-Qwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ3_S-00001-of-00002.gguf` | `638fbd42a01c7b39a9b7b21c5c8dc5eb1876222d8bd268d471304b647fcd6f94` |
| `Swift-Qwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ3_S-00002-of-00002.gguf` | `091a4f6a53697a12a2ea1e5e1d61414410d50c0d44e971304602bba6873fd23d` |

Download `strata/rt/{dense.bin,dense.txt,experts.bin,draft_vocab.bin}` from
that same revision to `/var/lib/private/strata/mtp-swift-1.5/rt/`, verifying
the binary files against the repository's LFS SHA-256 values. These are the
publisher-supplied draft runtime, not a Swift-trained MTP head: the model card
states that Swift has no dedicated MTP head. Draft acceptance and speed must
be measured on this model; earlier Orca measurements do not carry over.

Keep the downloaded `rt/` intact. Prepare `rt-en/` with the same `dense.bin`,
`dense.txt`, and `experts.bin`, but use the installed package's
`data/draft_vocab_en.bin` as `draft_vocab.bin`, matching the previous deployment's
English/code draft subset. This only restricts draft proposals; the target
model retains its full vocabulary and multilingual output.

Prepare its own dense pack and tokenizer using the installed engine:

```bash
S=$(dirname "$(dirname "$(readlink -f "$(command -v strata)")")")
cd "$S/share/strata"
sudo mkdir -p /var/lib/private/strata/mtp-swift-1.5/rt-en
for f in dense.bin dense.txt experts.bin; do
  sudo cp /var/lib/private/strata/mtp-swift-1.5/rt/"$f" /var/lib/private/strata/mtp-swift-1.5/rt-en/"$f"
done
sudo cp data/draft_vocab_en.bin /var/lib/private/strata/mtp-swift-1.5/rt-en/draft_vocab.bin
sudo "$S/bin/strata-python" tools/iq_pack.py \
  --gguf /mnt/data/models/swift-1.5/Swift-Qwen3.8-Flash-Next-GSQ-RCO-abliterated-IQ3_S-00001-of-00002.gguf \
  --out /var/lib/private/strata/packs/swift-1.5-iq3_s
```

The PLE table is in **shard 1**; both `--native` and `--ple-gguf` point there.
The pack keeps the GSQ-RCO tensors in their native form. The learned routing
profile is separate (`expert-profile-swift-1.5-iq3_s.bin`). Preserve
`--spec 4`, the supplied MTP runtime, 131072 context, two slots, and 13 CPU
workers. Prompt chunks are capped at 64 tokens, with one GPU expert-cache slot
(the remaining experts run on the CPU) and `--mtp-max-t 4` to avoid extra
5/6-token suffix-window graphs. Together with the English/code draft subset,
these bounds leave room for prompt scratch and lazy CUDA graphs on 8 GiB.
Automatic prefill allocation failed at startup; smaller prompt chunks alone
loaded but exhausted memory during decoding. These settings change batching,
caching and speculation, not the context limit or target model weights.
API URLs and authentication are unchanged; the advertised model ID
is `swift-1.5-qwen3.8-flash-next` (Strata also accepts existing client aliases).

Use the real `/var/lib/private/strata` state path for preparation; systemd
manages `/var/lib/strata` as its DynamicUser symlink. The engine log is
`/var/lib/strata/strata.log`; server progress is in the journal. After
`rebuildHost llm1`, explicitly restart Strata and verify loaded health,
authenticated inference, and rejection of unauthenticated API calls.
The old Orca shards may be removed to make room; rollback then requires
re-downloading them and restoring the old pack/configuration.

Validated and deployed on 2026-10-17: both GGUF SHA-256 checks and the supplied
runtime binary checks passed; the dense pack reported 96 exact conversions,
zero rounded conversions, and zero maximum conversion error. The final
secret-free host check, live-secret deployment, and explicit restart passed.
The running system is
`/nix/store/df0dhi20pfq4nsmxq2sz0l1xhfg1wnf9-nixos-system-llm1-26.05.20260924.c508844`.

Live checks passed loaded health and model discovery through loopback and the
LAN proxy, 401 without authentication and 200 with it on the direct API,
arithmetic and code generation, two concurrent short requests, the previous
model-name alias, and the Responses API. A fresh 1,456-token prompt completed
correctly in 35.1 seconds; two concurrent 1,160-token requests completed
correctly in 29.0 and 57.9 seconds. These are functional smoke checks, not a
quality or throughput benchmark. After prompt scratch allocation, the GPU had
about 215 MiB free; this remains a tight 8 GiB configuration, below upstream's
512 MiB warning threshold. Full 131072-token operation and sustained-load
performance have not been qualified. Earlier Orca throughput does not apply.

The three old Orca GGUF shards were removed; `/mnt/data` had about 69 GiB
free afterward. The pinned download manifest is stored beside the Swift
shards. Old packs/draft artifacts remain, but rollback also needs the removed
Orca weights to be downloaded again.

The following engine qualification and performance sections record the
**previous Orca IQ4_XS model**, unless explicitly dated as Swift validation.
Their throughput, memory use, draft acceptance, and model-output parity are
historical evidence, not qualification of Swift IQ3_S.

### Engine patch

Ported to 0.1.43.1 on 2026-10-13. Upstream had meanwhile added `--batch-mtp`
(per-slot drafters on the shared draft weights, one draft per slot, variable
row groups per slot with prefix commits) and the adaptive tier in batch
windows, so the port builds on those instead of the 0.1.39 code: the patch
now adds three drafts per slot to upstream's `--batch-mtp`, the one-GPU
pipelined batch windows, the native hyper-connection reads, the direct slot
copies and the IQ4_XS CPU kernel. With it the expert cache has 590 slots
instead of 302. Upstream's `tools/batch_test.py` (2 slots, 1 slot alone; 96 and
256 tokens, `--adapt-every 1000000`) gives every slot exactly its solo tokens.

`hosts/llm1/strata-performance.patch` changes the engine for this card and
for two requests at once. Each switch below restores upstream's behaviour for
its part. Upstream's exactness test (`tools/batch_test.py`: every slot of a
batch produces exactly its solo greedy tokens) passes with the patch, for two
slots and for one.

- **Hyper-connection projections in their GGUF form.** `--compat-bf16` turns the
  192 `hc_*_down/up` matrices (IQ4_XS/IQ4_NL, 328 MiB) into BF16 copies
  (1,200 MiB), which every decode window reads. The patch dequantizes the 4-bit
  blocks in registers instead, to the same FP32 weights. The prompt path
  dequantizes them to BF16 right before its GEMM, the same bits the pack held.
  The 872 MiB saved goes to the expert cache (730 to 1,051 slots for one
  request) or to the second request's state. `STRATA_HC_NATIVE=0` keeps the
  BF16 copies.
- **Drafts in batch windows.** With `"parallel": 2` each slot gets its own MTP
  drafter on the shared draft weights (about 50 MiB each), and each batch window
  verifies its token plus three drafts. Upstream verifies one token per slot,
  without drafts. The span is fixed at four rows per slot: every distinct window
  layout is its own CUDA graph, and each graph takes about 35 MiB of VRAM on
  this card. `STRATA_BATCH_DRAFTS_N=1..3` sets the drafts per slot (1 is
  upstream's `--batch-mtp`).
- **Pipelined batch windows.** With `--spec-split`, a window of two slots runs as
  two groups, one per slot. The CPU computes one slot's experts while the GPU
  runs the other's layers. A slot that is alone is split like a solo window.
  `STRATA_BATCH_SPLIT=0` keeps one group (upstream; only a layer split
  pipelines there, with `--batch-groups`).
- **Direct slot copies.** Moving a conversation between the main session and a
  slot copies its device state on the device and its K/V host copy once.
  Upstream goes through a host image, which takes about twice as long.
  `STRATA_DIRECT_COPY=0` restores that.
- **A single-token IQ4_XS gate/up kernel for the CPU pool.** It handles both rows
  in one pass with two sub-blocks per AVX2 register: 1.36x ggml-cpu's dot in
  isolation (relative difference 1e-7), and 10% less CPU time in batch windows,
  where most expert groups hold one token. `STRATA_IQ4XS_GU1=0` uses
  ggml-cpu's dot.
- **Reuse the CPU activation layout.** `strata-activation-reuse.patch` adds
  `STRATA_IQ4XS_PACK_ACT=1`: the single-token IQ4_XS kernel permutes its Q8_K
  activation bytes once per call, then reuses them for every gate/up row.
  Integer lane sums, FP32 accumulation order and SwiGLU remain the same.
  The workspace is bounded at 8 KiB per worker; wider inputs and single-row
  tasks use the original path. `iq4xs_gu1_parity` compares both paths bit for
  bit, including partial rows and the workspace fallback. Set the switch to
  `0` to retain the previous kernel.
- **Decode IQ4_NL nibbles in wider AVX2 lanes.** `strata-cpu-decode.patch`
  adds `STRATA_IQ4NL_WIDE=1` for the CPU down projection. It preserves integer
  lane sums and FP32 accumulation order; the single-token ggml dispatch stays
  unchanged. `iq_avx2_parity` compares the original, wider and dispatch paths.
- **Fuse native dense weight preparation.** `strata-prefill.patch` adds
  `STRATA_PREFILL_FUSED_WIDEN=1` for the Q5_K and IQ4_XS dense SGEMM paths.
  It dequantizes directly into their FP32 buffer while explicitly preserving
  the previous FP16 rounding. This removes the intermediate FP16 buffer write,
  read and widening launch. `dequant_fused_parity` compares every output bit
  against the two-stage path; unsupported types retain their existing path.
- **Keep checkpoints when returning to solo.**
  `strata-slot-checkpoints.patch` carries the slot's turn checkpoints back
  with its live K/V state. Previously only a partial prompt restore or an
  explicit checkpoint restore kept them; a full live restore discarded them.
  A second admission into the same slot then lost the next turn's reuse point.
  The existing token, image and extent checks still decide which checkpoints
  are valid. `tests/check-strata-slot-checkpoints.py` exercises repeated
  transfers with a private engine and compares the continuation and next turn
  against uninterrupted solo references. It requires an available GPU and
  an explicit model config, executable, tools directory and output path.

## Performance

Measured on devenv (VM 202, the same GPU, node and vCPU count) on 2026-10-06
with four prompts at T=0 (code, prose, an edit of a
4.4k-token file, and a thinking question; 512 tokens each), the first two at
once for the two-request numbers, and a 13k-token prompt. hv1's nightly backups
were running, so each run read the prompts twice and kept the second pass,
when the n-gram rows were already cached (see "Nightly backups").

| Configuration | One request, t/s (code / prose / edit / think) | Two requests | Prompt t/s (4.4k / 13k) |
|---------------|------------------:|-----------------:|-----------------:|
| before: upstream engine, `--kv-resident 32768`, `--pool-workers 13` | 22.1 (21.7 / 19.7 / 21.7 / 25.4) | one at a time | 180 / - |
| **deployed: engine patch, `--pcie-frac 0 --spec-split`, `--kv-resident 20480`, `"parallel": 2`** | **33.4 (33.1 / 28.9 / 34.4 / 37.0)** | **36 t/s together, 18 each while both decode** | **138 / 147** |
| the same without `"parallel"`, `--kv-resident 32768` | 32.8 | one at a time | 208 / 232 |
| **llm1 after the move (same config, no backup running)** | **33.75 (34.1 / 28.1 / 34.6 / 38.2)** | **30.5 t/s together, 19.3 / 15.5 per stream** | **139 / 149** |
| llm1, Orca MTP head (2026-10-06 22:45) | 33.85 | 34.4 t/s together, 17.2 each while both decode (fresh start) | ~138-139 / - |
| **llm1, + vCPU pinning (22:52)** | **34.23** | **37.0 t/s together, 18.5 each while both decode** | **~138-139 / -** |
| llm1, stock 0.1.43 with `--batch-mtp` (2026-10-12 00:55, no patch) | 35.12 (34.5 / 30.1 / 37.1 / 38.8) | 26.2 t/s together, 13.3 each (windows 132 ms, 3.5 rows, 79% of proposals accepted) | - |
| **llm1, 0.1.43.1 + ported patch (2026-10-13 13:35)** | **35.23 (34.1 / 32.4 / 36.0 / 38.4)** | **36.5 t/s together, 19.8 / 18.6 per stream (windows 145.5 ms = CPU experts 109.3 + GPU wait 11.6 + commit/drafts 12; 5.4 tokens; 63% of 3 drafts per slot accepted)** | 123 / - |
| the same + `STRATA_ADAPT_OVERLAP=1` (deployed; one pass) | 36.48 | 35.0 t/s together (first pass, cold) | - |
| the same without `--batch-mtp` | - | 23.1 t/s together, 11.6 each | - |

The llm1 row was measured on 2026-10-06 at 18:56 with the same client and
prompts (second of two passes), right after the move: llm1 matches devenv. The
last two rows are from 22:20-23:10 the same night; the two-request numbers are
the engine's batch windows with both slots active (strata.log's
`strata batch:` lines). The vCPU pinning (see "hv1 VM config") made two-slot
windows 153.7 ms (CPU experts 116.0 ms) instead of 155.6-161.9 ms (CPU experts
120-126 ms) unpinned: about 3-5%.

What each change gave (one request, mean t/s, earlier the same night with a
single pass): `--pcie-frac 0` 21.3 to 27.3 (the GPU had waited about 64 ms per
window for PCIe expert copies), `--spec-split` 31.5, and the engine patch 33.4.
Without the patch, two requests do not fit on the card at 131072 tokens (the
draft head runs out of VRAM); upstream's batch windows ran at 11-12 t/s per
request.

A batch window of two requests verifies about 8 rows (each request's token plus
3 drafts). With short contexts and pinned vCPUs it keeps 5.69 tokens in
153.7 ms (37.0 t/s together, 18.5 each):

| Part of a two-slot window | ms |
|---------------------------|---:|
| CPU experts | 116.0 |
| waiting for the GPU's part | 12.1 |
| drafting | 12.4 |
| host orchestration | ~13 |

The CPU pass is bound by memory bandwidth: about 44 distinct experts per layer,
read at 46 GB/s, against the guest's measured 64 GB/s read limit. At 50-60k
tokens of context (unpinned) a window takes 162-166 ms (CPU experts 127,
drafting 14) and keeps 5.3 tokens, about 16 t/s each. DRAM bandwidth alone
would allow about 21-24 t/s each if all the non-CPU time overlapped; that needs
engine work (overlapping one slot's drafting with the other slot's last layers,
batched drafting for both slots), not configuration. A request alone gets
the single-request path again (about 0.1 s to move it), so the two-request
penalty applies only while both decode. Two slots cost the prompt path its large
chunks (1,024 tokens instead of 4,096), so long prompts read about 1.6x slower.

Long contexts are slower. Two agents ran with 47k- and 40k-token contexts, three
turns each with tool results, during the backup window. The prompts read at
134-140 t/s, and an agent decoding alone ran at 25-33 t/s. While both decoded,
each got only 3-15 t/s. Part of that is the backup's disk stalls. Part is that
moving a request into a slot leaves its KV cache cold in VRAM (upstream's
`kv_stream_reset`), so attention reads from RAM until the hot positions are
cached again.

While one agent's prompt (a tool result or a new conversation) is read, the
other agent decodes only between prompt chunks. `STRATA_BATCH_DECODE_SHARE`
(engine environment, default 0.5) gives it half as long as each chunk took,
so a third of the time, and the prompt path borrows about 467 cached-expert
slots meanwhile, so those windows also run slower. In the 60k baseline the
decoding agent made about 8 t/s while the other read a 47k-token prompt.
Prompts are admitted one at a time: an agent's next turn waited about 5 minutes
behind the other agent's 47k-token prompt.

llm1 sets `STRATA_BATCH_DECODE_SHARE=1.0` (half the time). With two agents at
about 20k tokens of context, three turns each, a decoding agent's turn during
the other's prompt read went from 9.1 to 12.3 t/s (client-measured); a prompt
read beside a decoding agent takes 2x instead of 1.5x as long as alone. Mean
client decode per turn: 22.5 t/s (1.0) against 12.3 (0.5, in a run that also
contained the re-read below).

The previous configuration set `STRATA_PARALLEL_SOLO=0` in the unit's environment
(the server reads it, not the engine, so it is not in the config's `env`): a request
left alone in a batch slot stayed there instead of going back to the solo path. With
the default, a request moved slot -> solo -> slot -> solo lost its cached state
on the second return and was read again from scratch (22,055 tokens in 156 s;
about 15 minutes at 128K). With it off, every follow-up turn reused its prefix
and mean client decode per turn was the same (22.7 against 22.5 t/s). The cost:
a lone agent in a slot decodes in batch windows (about 30 t/s) instead of the
solo path (about 34 t/s). A request that starts while nothing else runs still
takes the solo path.

Two agents with long contexts (2026-10-06 23:31 to 2026-10-07 00:12, final
configuration: pinned vCPUs, Orca MTP head, `STRATA_BATCH_DECODE_SHARE=1.0`,
`STRATA_PARALLEL_SOLO=0`; bench client `agents` mode: two agents start 1 s apart,
each with a large code document as context, then 3 turns, each appending a
~1.4-1.8k-token tool result and generating up to 384 tokens; client t/s counts
from the first to the last streamed token of a turn, so it includes pauses while
the other agent's prompt is read):

| Context per agent | Client t/s per turn, mean (min) | Both decoding (engine) | Notes |
|---|---|---|---|
| ~50-60k, before tonight (unpinned, base head, share 0.5) | 18.3 (8.0) | 162-166 ms windows, 5.3 tokens: ~16 each | an agent's next turn waited ~5 min behind the other's 47k prompt |
| ~50-60k, final | 23.0 (10.4) | — | every follow-up turn reused its prefix |
| ~100-110k, final | 12.3 (6.0) | 143.6 ms windows, 4.38 tokens at 5.8 rows: ~15 each | prompts read at 136-139 t/s (107k tokens: 12.9 min); KV streaming hit VRAM for 58-71% of block reads; while the other agent's prompt is read, the decoding agent's windows see almost no GPU expert hits (0.1-0.7 per layer) because the prompt path borrows the cache slots |

The goal of two agents at 128K each decoding at 20 t/s or more is not met on
this hardware: about 18.5 t/s each with short contexts, ~16 at 50-60k and ~15 at
100-110k while both decode; one agent alone runs at ~34 t/s (~30 when left alone
in its slot). The remaining levers are engine work (overlap a slot's drafting
with the other slot's last layers, batched drafting for both slots, upstream
v0.1.40's drafter and QSA changes) and more VRAM (a larger GPU holds several
times more experts, which is the only change that removes most of the CPU
expert pass). The configuration experiments above did not meet that target; they do not establish
an absolute hardware limit. Re-evaluate engine changes against the same workload
(see Host tuning).

Measured and not used:

| Change | Result |
|--------|--------|
| `--pool-workers 20` | unpinned: batch windows 3.5% faster, one request unchanged, 7 more busy vCPUs. Pinned: 153.4-153.9 ms per window against 153.7 with 13 (the expert pass is DRAM-bound), so 13 stays |
| `--pool-workers 27` (no split) | 2% slower than 13 |
| `STRATA_BATCH_DRAFTS_N=2` | batch windows 135 ms but 4.6 tokens: 6% less throughput |
| `STRATA_IQ_PREFETCH=4096` (CPU kernels' prefetch distance, default 2048; 0.1.43.1) | one request 35.1, two 34.0 together (first pass): no gain |
| `--spec 6` (0.1.43.1) | one request 35.1, two 34.1 together (first pass): no gain |
| 15% of a batch window's missed experts over PCIe (DMA) | 170 ms instead of 161: the copies take the same DRAM bandwidth |
| skipping the CPU experts of batch drafts under min-p | 10% less CPU time, 5% fewer tokens per window: break-even |
| `STRATA_FUSE_HEAD_GR=1`; a one-warp-per-row MMVQ kernel | within noise (+0.5%, +1.4%) |
| `--prefill 2048` with two slots | does not fit; falls back to 512-token chunks (95 t/s) |
| `STRATA_IQ4XS_GU1=0` (the patch's CPU kernel off) | batch CPU time 10% higher; one request -2% |

Lower-bit experts do not help on this CPU. ggml-cpu's single-row `vec_dot` on
one core of an E5-2690 v4 (AVX2; measured on devenv, the same CPU model) reads
IQ4_XS weights at 4.6-6.7 GB/s from cache (5.6 from RAM: memory-bound), IQ3_XXS
at 1.8-2.1 GB/s (compute-bound), and IQ3_S at 1.2-1.5. Per weight IQ3_XXS costs
about 2.6x the CPU time of IQ4_XS, so OrcaRouter's IQ3_XXS file (18% fewer
bytes) would make the CPU expert pass slower.

### 0.1.44 migration and expert streaming

The local performance patch is rebased onto 0.1.44, retaining the native
hyper-connection projections, three batch drafts, split verification, direct
slot copies and AVX2 IQ4_XS kernel. The ggml revision is unchanged. Upstream
adds sm_61 expert mode 8, Pascal matrix-vector dispatch and wider dense-weight
dequantization. Their upstream P40 measurements are not GTX 1070 results.

[FreeToken](https://github.com/FlashML-org/FreeToken) supplies a useful comparison:
its hybrid scheduler divides missed experts using CPU and PCIe bandwidth measured
while both run, and its prompt path double-buffers streamed expert layers.
Strata has an ahead-streaming prompt path and an adaptive GPU expert cache;
the current smaller prompt chunks use a routed staging ring (see the 0.1.44.1
measurements below). More expert traffic over PCIe also reads
host DRAM, so it can compete with the CPU pool. Keep `--pcie-frac 0` unless a
same-workload measurement beats it; the historical 15% DMA experiment above lost.
The current kernel-copy path can be checked separately without selecting the
older DMA path, which upstream documents as vulnerable to a driver-lock stall.

The package includes focused matching-hardware checks under
`libexec/strata/{gemm_f32_parity,mmvq_il_parity,dequant_wide_parity}`. Run these
with the service stopped to release VRAM. `gemm_f32_parity --quick` checks the
optional `STRATA_DENSE_F32=1` prompt route against this package's cuBLAS; it is
a sampled correctness check, not a full chunk-size sweep. On 2026-10-13 the
GTX 1070 passed all 134 sampled shapes with CUDA 12.9 / cuBLAS 12.9.1.4,
all 360 dequantization cases, and every matrix-vector parity case. The
ported engine also passed `batch_test.py --batch 2 --n 2` and `--n 1`
(64 greedy tokens per slot, fixed adaptive cache, `STRATA_IQ_MT_MIN=1`).
The service enables `STRATA_DENSE_F32=1`; prompt buffers still fall back to
the FP16 route if its extra allocations cannot fit.
`--prefill-head-alias` is unsuitable here because upstream refuses it with batching.

Deployed and smoke-checked on llm1 on 2026-10-13 (one short sample per
configuration, not a benchmark sweep): temperature 0, reasoning disabled,
256 output tokens for a merge-intervals coding prompt and a B-tree explanation;
the two-request test starts both concurrently. The prompt check reads 1,123
fresh tokens of repeated text. Context limit remains 131072 and parallelism 2.

| Check | 0.1.43.1 + patch | 0.1.44 + ported patch + FP32 prompt path |
|---|---:|---:|
| Solo client decode (completion tokens / first-to-last-token time) | 38.0 t/s | 41.2 t/s; warm recheck 42.5 |
| Two requests, total completion tokens / wall time including admission | 37.9 t/s | 36.6 t/s |
| Two-request engine window | 141.25 ms | 135.62 ms |
| Fresh prompt, engine-reported | 134.7 t/s | 145.5 t/s |

The batch windows became shorter, but draft acceptance in this sample fell
from 72.0% to 66.5%, so there is no demonstrated two-request throughput gain.
These short checks do not requalify long-context throughput or prove a hardware
maximum. The source host check, external-secret host build and activation passed;
the active engine at that point was 0.1.44.

One bounded expert-streaming check used `strata_tune: {"pcie_frac": 0.2}`
on the same solo coding prompt, between the two CPU-miss runs. It reached
27.9 t/s versus 41.2 and 42.5 with `pcie_frac: 0`; the returned completion was
256 tokens in each case. This uses the current kernel-copy path, not the older
DMA experiment. The service therefore keeps `--pcie-frac 0`. Prompt expert
staging and asynchronous adaptive-cache uploads remain enabled.

### 0.1.44.1 migration

The patch applies to the 0.1.44.1 release; the ggml commit and CUDA 12.9 toolchain
remain pinned. This release also fixes reasoning-effort routing in the Responses
API. The package runs upstream's effort-routing tests alongside its authentication
tests, and the separately built workspace harness keeps its route tests.

Deployed on 2026-10-14 after the secret-free host check, external-secret host
build, 34 upstream API tests and 26 harness authentication/workspace tests passed.
The final package passed the GTX 1070's 360 dequantization cases, matrix-vector
parity suite and 134 sampled FP32 GEMM shapes. Both `batch_test.py --batch 2 --n 2`
and `--n 1` produced all 64 greedy tokens per slot identically to solo decoding
with a fixed adaptive cache and `STRATA_IQ_MT_MIN=1`. The supported host rebuild
and explicit service restart succeeded; the active binary is 0.1.44.1, health
reports a loaded model with 131072 context, and API authentication checks passed.
The temporary test override was removed. The model, quantization, context limit
and two-request capacity are unchanged.

After the final restart, the same 256-token coding and B-tree checks measured
40.2 tokens/s solo and 38.5 tokens/s combined (including admission). The initial
0.1.44 samples were 41.1 and 39.5 respectively: this migration demonstrates no
additional decode speedup. A fresh 1,571-token prompt read at 135.0 tokens/s.
The live Responses API also completed a request with `reasoning.effort: none`,
returning a message and zero reasoning tokens.

Three focused scheduling trials on 2026-10-14 were not retained:

- `--adapt-async 1` reduced the two-slot adaptive wait from 1.85 to 0.15 ms per
  window, but solo client decode was 40.5 versus 41.1 tokens/s and total
  two-request throughput was 38.6 versus 39.5. The existing
  `STRATA_ADAPT_OVERLAP=1` remains preferable in this sample.
- `STRATA_PREFILL_STREAM_MIN=512` let the current 768-token prompt chunks use
  ahead streaming through 199 slots instead of routed staging through eight.
  A fresh 1,571-token prompt slowed from 135.5 to 118.9 tokens/s. The larger
  ring borrowed 430 instead of 239 expert-cache slots. The default threshold
  remains in place; larger qualifying chunks still use ahead streaming.
- `--adapt-every 1` refreshed the cache every window instead of every four.
  Solo decode fell to 40.0 tokens/s and total two-request throughput to 37.6,
  against 41.1 and 39.5 at baseline. The default cadence stays in place.

An experimental patch also removed empty PCIe kernels from the verify graphs.
With a fixed expert cache, its output tokens matched the old path through solo,
slot, fresh-prompt and zero/nonzero PCIe transitions. Decode stayed within
measurement noise, so the extra graph-management code was not retained.

These apply FreeToken's bandwidth and memory-budget lessons to this host rather
than assuming that more streaming must be faster. They are short comparisons,
not a new long-context qualification or a proof of maximum hardware throughput.

### Checkpoint and activation reuse

The 2026-10-14 follow-up fixes the reason solo promotion had been disabled.
Returning a full live slot cleared the main session's checkpoints. The next
admission overwrote the slot with that empty checkpoint list, so a later turn
whose rendered history omitted reasoning had no prefix to restore. The engine
now transfers those checkpoints with the state and applies the existing
prefix/extent filter. `STRATA_PARALLEL_SOLO=1` lets a request left alone return
to the faster solo decoder.

The focused full-model regression reproduced two slot/solo transfers followed
by a turn with rewritten assistant history. Before the fix, it reused zero
tokens and read the prompt in 7,541 ms. Afterward, it reused the 821-token turn
checkpoint and read only the suffix in 562 ms. All 64 continuation tokens and
all 32 follow-up tokens matched their uninterrupted solo references. This
demonstrates avoided rereading, not higher throughput on a fresh prompt.

The CPU optimization separately keeps the existing IQ4_XS arithmetic while
reusing its permuted activation layout across rows. On llm1's E5-2690 v4,
the focused 127 MiB, one-thread comparison measured 0.338 to 0.323 ms per
gate/up expert (4.4% less time; three short passes). Its 240 synthetic cases
were bit-identical, and the broader AVX2 parity suite passed. With the service's
actual `STRATA_IQ_MT_MIN` default and a fixed expert cache, enabling it preserved
every one of 384 solo/single-slot/two-slot output tokens. Two-slot throughput
in that small check moved from 26.7 to 27.0 tokens/s; one-slot throughput was
unchanged at 26.2. These fixed-cache checks are correctness gates and differ
from normal adaptive-cache serving; they do not establish a broad decode gain.

Both patches are deployed on llm1. The host source check, live-secret system
build, 34 upstream API tests and 26 harness tests passed. After activation,
the service reported the expected engine and both switches enabled, with no
runtime drop-ins. Health, authenticated access and rejection of unauthenticated
requests passed. Streamed requests also exercised a live slot returning to
solo: it restored 244 tokens in 15 ms and completed its remaining 37 tokens.

The short live check measured 40.7 tokens/s solo and 38.3 tokens/s combined,
against 39.8 and 38.7 before these changes on the same prompts. Solo rate uses
the interval between first and last content; combined rate includes prompt
admission. Cache warmth differed, so these samples do not demonstrate a gain
in combined throughput. The measured gains are the preserved turn reuse and
the CPU kernel component above.

The model, quantization, 131072-token context, two-request capacity and sampling
settings are unchanged. Long-context performance has not been requalified.

### Exact CPU decode and dense preparation

The optimizations deployed on 2026-10-15 preserve the existing quantized weights
and arithmetic.
On llm1's E5-2690 v4, the two-token, 25-expert CPU microcheck measured IQ4_NL
down projection time of 0.400 to 0.380 ms per expert (5% less), and combined
gate/up plus down time of 0.869 to 0.847 ms (2.5% less). The installed AVX2
parity tool passed, including exact original/wider/dispatch rows for one
through eight tokens.

On its GTX 1070, fused Q5_K preparation fell from 1.3630 to 0.6425 ms (2.12x)
and IQ4_XS preparation from 0.8381 to 0.3768 ms (2.22x), stable over three
passes. All 96 bitwise cases passed. These measure weight preparation alone,
not whole-prompt throughput. The combined secret-free llm1 check also passed,
including 34 upstream API and 26 harness tests.

The old deployed executable and the new package with both switches enabled
produced identical token IDs and finish reasons for all 272 generated tokens:
16 tokens after a fresh 1,473-token prompt, 64 solo tokens, two slots of 64 tokens each and
64 one-slot tokens. In this fixed-cache check, prompt time fell from 9,746.7
to 9,618.8 ms (1.3%), solo decode from 1,954.5 to 1,937.7 ms (0.9%), total
two-slot time from 5,343.7 to 5,295.6 ms (0.9%) and one-slot time from 2,677.0
to 2,655.7 ms (0.8%). This was one short A/B comparison, not a statistical
whole-service speed claim.

The external-secret system build, supported `rebuildHost llm1` and explicit
service restart passed. Both switches are enabled declaratively. The installed
package passed the CPU parity and 96 GPU bitwise cases; service health reported
a loaded model, and the models endpoint returned 401 without authentication
and 200 with it. The deployed engine is
`/nix/store/jvj59wazzzi0ggfmxi5qc65mdw7bfwfx-strata-0.1.44.1`; the system is
`/nix/store/9apxfy5ry7ssw40x3cb7cvfprarbgq3s-nixos-system-llm1-26.05.20260924.c508844`.

Freshly restarted old/new live checks measured 40.13 to 40.30 tokens/s solo
(256 tokens), 38.26 to 38.29 tokens/s combined (512 tokens, including admission),
and 131.4 to 131.7 prompt tokens/s for an uncached 1,589-token prompt
(12,091.7 to 12,061.9 ms). These are essentially unchanged within smoke-test
noise. The model, quantization, 131072-token context, two-request capacity,
13 CPU workers, `--spec 4` and `--pcie-frac 0` remain
unchanged. Long-context runtime performance has not been requalified.

The reusable focused gate compares token IDs and finish reasons within each
execution mode. It keeps the existing `STRATA_IQ_MT_MIN`, fixes the adaptive
cache and disables conversation caching.
Use an idle GPU and a batch-test-format model config with its `env` removed;
export the common service engine environment in the calling shell. The config
and output directory must stay outside this checkout, and the output directory
must not already exist:

```bash
python3 tests/check-strata-optimizations.py \
  --baseline-exe "$BASELINE/bin/strata" --exe "$CANDIDATE/bin/strata" \
  --config "$MODEL_CONFIG" --tools "$CANDIDATE/share/strata/tools" \
  --off-env STRATA_IQ4NL_WIDE=0 --on-env STRATA_IQ4NL_WIDE=1 \
  --off-env STRATA_PREFILL_FUSED_WIDEN=0 --on-env STRATA_PREFILL_FUSED_WIDEN=1 \
  --output-dir "$QUALIFICATION_OUTPUT"
```

Two trials were rejected. Vectorizing the separate FP16 widening kernel passed
40 bitwise cases but changed large-buffer conversion time by only about 0–0.4%.
Coalescing PLE reads contained in an existing straddling read reduced a synthetic
neighboring-row fixture from seven reads to six with identical bytes. Decode
heads address disjoint ranges, however, and no useful real-workload hit rate was
established. Neither trial is retained; the direct-I/O backup limitation remains.

### Wider IQ4_XS decode and direct draft transfers

The second 2026-10-15 optimization extends the lane-preserving CPU nibble
decode to multi-token IQ4_XS gate/up rows (`STRATA_IQ4XS_WIDE=1`). On llm1's
E5-2690 v4, the focused two-token, 25-expert comparison measured median
gate/up time of 0.477 to 0.463 ms per expert and combined gate/up plus down
time of 0.848 to 0.834 ms (1.7% less). The existing IQ4_NL optimization
was enabled in both arms. The installed `iq_avx2_parity` passed with zero
failures, including exact original/wide results for one through eight tokens.

`STRATA_DIRECT_MTP_COPY=1` removes the temporary full draft-KV snapshot on
slot/solo transfers. It uses the existing copier to transfer the authoritative
host pool and reconstruct the destination's resident ring. If the drafters
have different KV residency modes, it retains the existing save/restore path:
each drafter can independently fall back from a host-backed ring to resident
KV during loading. This avoids temporary allocation and copying without adding
a persistent buffer or reducing context or batch capacity.

The packaged `conversation_snapshot_test` passed 4,225 checks on llm1,
including 54 new fixtures (324 assertions) covering direct draft copies,
partial/wrapped pages, zero extent, different ring capacities and both
transfer directions. The full-model baseline/candidate gate preserved all
272 token IDs and finish reasons across fresh-prompt, solo, one-slot and
two-slot execution. A repeated slot/solo fixture also preserved all 64
continuation and 32 follow-up tokens, reused the 821-token checkpoint and
read the follow-up suffix in 543 ms. Its two return transfers took 16.6 and
16.4 ms; no baseline transfer timing was collected, so these are functional
evidence rather than a measured transfer speedup.

The small fixed-cache full-model sample was 0.6% slower solo, 1.7% slower
with two slots and 3.2% slower with one slot. A fresh-restart live comparison
with both switches enabled was essentially unchanged: solo 40.48 to 40.58
tokens/s, two requests combined 39.07 to 39.13 tokens/s (including admission),
and a fresh 1,580-token prompt 133.0 to 132.6 tokens/s (11,879.1 to
11,914.5 ms). Both live prompts' output hashes matched the baseline.
These short samples demonstrate no meaningful whole-service speedup; the
measured gain is the CPU component above. Long-context throughput remains
unqualified. Weights, quantization, sampling, 131072-token context, two-request
capacity, 13 CPU workers, `--spec 4` and `--pcie-frac 0` are unchanged.

The combined secret-free host check passed, including 34 upstream API and
26 harness tests. The candidate live check also passed authentication
(401 without a key, 200 with one) and a Responses API request.

The final secret-free check, external-secret system build, supported
`rebuildHost llm1` and explicit Strata restart passed. The running service
has both new switches and the previous optimizations enabled declaratively,
with no runtime drop-ins. Final health reported the loaded model and
131072-token context; authenticated/unauthenticated access returned 200/401,
and the Responses API completed with `ready`. The deployed engine is
`/nix/store/p67hb08sricqa9mhirwm7wlwicl60wgf-strata-0.1.44.1`; the system is
`/nix/store/wk2dhgn2jfwdnk4cp9cj38m5dm4cmk4l-nixos-system-llm1-26.05.20260924.c508844`.

A further prefill activation-reuse idea was rejected before implementation:
consecutive GDN projections widen the same activations, but avoiding that
small conversion would need additional buffer-lifetime and fallback handling
for little expected benefit. Routed expert staging already keeps transfers
ahead and overlaps shared-expert work by default; no prefill change was added.

### Nightly backups

Strata reads the 28.8 GB n-gram (PLE) table with direct I/O from llm1's data
disk on hotData, 16 rows per token, prefetched as drafts are made. While hv1's
nightly vzdump runs (01:00, all VMs; a full read of a large disk can take hours),
those reads slow from about 0.15 ms to 0.5 ms typical and 80-800 ms at the 99th
percentile, and decode can fall to a third. A row the engine has read before is
cached in its 1M-row cache, so repeated text is not affected. `--ple-io ram`
avoids the disk entirely, but it locks about 27 GiB more RAM. On 2026-10-14
the running service left only 31-32 GiB available, so this would leave roughly
4-5 GiB before further conversation/checkpoint growth. It remains disabled;
the earlier estimate of 16 GiB spare did not reflect the current service.

### Host tuning

Applied on hv1 on 2026-10-06 (operator-approved):

- **vCPUs pinned 1:1 with an SMT guest topology.** See "hv1 VM config". Two-slot
  windows got 3-5% faster.

Measured on 2026-10-06 and reverted:

- **Uncore floor and C-states.** Package 1's uncore floor at its 2.7 GHz maximum
  (`/sys/devices/system/cpu/intel_uncore_frequency/package_01_die_01/min_freq_khz`)
  plus C1E/C6 disabled on node 1's CPUs: 157.3 ms per window against 155.6 ms
  without. The pool workers spin with `_mm_pause` for 20 ms before they sleep,
  and under load the uncore already runs at 2.7 GHz, so neither C-state limits
  nor KVM halt polling matter for decode.
- **`--pool-workers 20`.** No gain with pinning (see the table above).

Still open:

- **More memory bandwidth.** Decode is bound by node 1's DRAM bandwidth (the
  CPU pool reads experts at 46-53 GB/s). hv1 has 4 x 32 GB DDR4-2400 2R per
  socket, one DIMM per channel at 2400 MT/s, so node 1's ~64 GB/s guest read
  limit is already the platform's practical maximum. Adding node 0's bandwidth
  would take memory from the node-0 VMs.
- **Backup-proof n-gram reads.** Either restore hotData's mirror (the pool lost
  an NVMe to the GPU) or use `--ple-io ram` on llm1, which still needs about
  27 GiB for the table plus enough headroom for the current service's checkpoints
  and prompt buffers (see "Nightly backups").

## Update policy

llm1 takes part in the nightly fleet deploy like every other host, but the
engine and the driver stay fixed:

- **Strata** is built from the flake input `nixpkgsStrata`, pinned to nixpkgs
  `c508844` (the nixpkgsStable commit that built it on devenv). Lock-file
  updates do not move a rev-pinned input, and `renovate.json` disables it.
- **The NVIDIA driver** is `nvidiaPackages.mkDriver` at 580.173.02 with the
  hashes `legacy_580` had at that commit. The kernel and the rest of the system
  update with nixpkgsStable; the module is rebuilt at this version for each
  kernel and takes effect at the next reboot.
- **`strata` and `llm-api-mesh`** have `restartIfChanged = false`, so a switch
  never reloads the model (1-2 minutes) or cuts open requests. A changed unit
  takes effect at the next reboot or `sudo systemctl restart strata`.
  Everything else restarts normally.

To bump on purpose:

- Strata or its CUDA stack: change `nixpkgsStrata.url` to a newer commit and
  run `nix flake lock`, or edit `hosts/llm1/strata.nix` (see Notes). Benchmark,
  deploy, then restart `strata`.
- The driver: copy the new `legacy_580` attributes (version and hashes) from
  `pkgs/os-specific/linux/nvidia-x11/default.nix` in the locked nixpkgsStable
  into `hosts/llm1/llm.nix`, deploy with `rebuildHost llm1 --boot`, and reboot
  llm1. The driver must stay on the 580 branch.

## hv1 VM config

VM 210 was restored from `packages.x86_64-linux.llm1`, then set by hand on hv1
(the VMA's generated config has no GPU or NUMA settings):

```text
memory 106496, sockets 1, cores 28, cpu host
args -smp 28,sockets=1,cores=14,threads=2,maxcpus=28
numa 1, numa0 cpus=0-27,hostnodes=1,memory=106496,policy=bind
affinity 1,3,5,...,55 (the odd CPUs, node 1)
hookscript local:snippets/llm1-vcpu-pin.sh
hostpci0 0000:82:00,pcie=1
hotplug disk,network,usb (no memory hotplug: DIMM backends get no host-nodes)
allow-ksm 0, onboot 1, startup order=4, iothread=1 on scsi0 and scsi1
```

`sockets 1, cores 28` stays in the config, but QEMU uses the last `-smp`, so
the guest sees 14 cores x 2 threads (checked with `lscpu`). The hookscript pins
each vCPU thread after start: vCPU `2c` to host CPU `2c+1` (node 1's core c) and
vCPU `2c+1` to its hyperthread sibling `2c+29`. Strata puts its host thread on
core 0 and one pool worker per physical core, primaries first, so they land on
separate physical cores. Proxmox `affinity` only pins the whole process, hence
the hookscript. The `local` storage got the `snippets` content type for it
(`/var/lib/vz/snippets/llm1-vcpu-pin.sh`). The config before the change is
`/root/210.conf.pre-pin` on hv1.

```bash
#!/bin/bash
# Proxmox hookscript for VM 210 (llm1, docs/llm1.md "hv1 VM config").
# The guest sees 14 cores x 2 threads (args -smp); pin vCPU 2c to node 1's core c
# (host CPU 2c+1) and vCPU 2c+1 to its hyperthread sibling (2c+29), so Strata's
# one-worker-per-core placement lands on separate physical cores.
vmid=$1 phase=$2
[ "$phase" = post-start ] || exit 0
pid=$(cat "/var/run/qemu-server/$vmid.pid") || exit 1
for t in /proc/"$pid"/task/*; do
  name=$(cat "$t/comm" 2>/dev/null) || continue
  case $name in "CPU "*"/KVM") ;; *) continue ;; esac
  k=${name#CPU }; k=${k%/KVM}
  cpu=$(( 2 * (k / 2) + 1 + (k % 2) * 28 ))
  taskset -pc "$cpu" "${t##*/}" >/dev/null || echo "llm1-vcpu-pin: vCPU $k -> CPU $cpu failed" >&2
done
```

devenv (VM 202) gave up the GPU at the same time and moved to node 0:
memory 40960, 1x12 cores, `numa0 cpus=0-11,hostnodes=0,memory=40960,policy=bind`,
the even CPUs. The configs before the move are `/root/202.conf.pre-split` and
`/root/210.conf.pre-split` on hv1.

Every other VM is bound to node 0 the same way: `numa 1`,
`numa0 cpus=0-<vCPUs-1>,hostnodes=0,memory=<MiB>,policy=bind`, the even CPUs,
and no `memory` in `hotplug` (rp1, apps1, apps2 and db1 had it; with memory
hotplug the DIMM backends get no host node). Their configs before the change are
`/root/<id>.conf.pre-numa` on hv1. Placement measured on 2026-10-06 at 19:32
(memory in `qemu.slice/<id>.scope/memory.numa_stat`, anon + file):

| VM | Memory (MiB) | Node 0 (GiB) | Node 1 | CPUs |
|----|-------------:|-------------:|-------:|------|
| 201 rinf | 12288 | 1.7 | < 1 MiB | even |
| 202 devenv | 40960 | 14.3 | < 1 MiB | even |
| 203 rp1 | 4096 | 1.0 | < 1 MiB | even |
| 204 apps1 | 8192 | 5.8 | < 1 MiB | even |
| 205 apps2 | 16384 | 4.0 | < 1 MiB | even |
| 206 db1 | 8192 | 2.0 | < 1 MiB | even |
| 207 apps3 | 8192 | 7.6 | < 1 MiB | even |
| 210 llm1 | 106496 | 0.02 | 104.0 GiB | odd |
| 301 winsvcs1 | 16384 | 16.2 | < 1 MiB | even |

The node-1 remainder of each node-0 VM is QEMU's own process memory. Node 0 had
61.0 of 125.8 GiB free and node 1 12.4 of 126.0 GiB; node 0 falls to about
10 GiB free once every VM has touched all its memory. 101 (ubuntu-test, stopped)
is configured for node 0 too; 102 (w11test) is unchanged.

## Notes

- The model is in `/mnt/data/models` on llm1's data disk, bind-mounted
  read-only into `strata`.
- Strata is pinned to the `v0.1.44.1` tag. When bumping it, update the ggml
  commit from `third_party/ggml/VERSION.txt`, re-check the MTP fetch patch
  (`strata-mtp-fetch.patch`), and benchmark one and two requests against the
  Performance table.
- When bumping Strata, port `strata-performance.patch` (see "Engine patch"),
  then run upstream's `tools/batch_test.py` on llm1 with strata stopped
  (`--batch 2 --n 2` and `--n 1`, `--extra "--adapt-every 1000000"`, the
  config's paths under `/var/lib/private/strata`) and the benchmarks.
