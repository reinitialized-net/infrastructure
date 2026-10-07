# llm1 LLM Service (Qwen3.8-Flash-Next)

`hosts/llm1/llm.nix` serves Qwen3.8-Flash-Next-Uncensored (OrcaRouter IQ4_XS,
about 97 GB in three GGUF shards) on llm1 (VM 210 on hv1, `10.1.11.9`, mesh
`10.255.0.9`) with [Strata](https://github.com/Niko1221/Strata) on the
passed-through GTX 1070. `strata.service` starts at boot and listens on
`127.0.0.1:8080`. Until 2026-10-06 it ran on devenv.

## Endpoints

| Client location | Base URL | Notes |
|-----------------|----------|-------|
| LAN / VPN | `https://llm.in.reinitialized.net/v1` | rp1, ACME TLS, `internalOnly`; the web UI is at `https://llm.in.reinitialized.net/` |
| Mesh hosts | `http://10.255.0.9:1045/v1` | `llm-api-mesh.socket` forwards to loopback; WireGuard-encrypted |
| llm1 itself | `http://127.0.0.1:8080/v1` | Also serves the web UI |

Every route except `/health` and the web UI's static files requires
`Authorization: Bearer <key>` (Strata also accepts `x-api-key`). The model ID is
`qwen3.8-flash-next`; Strata answers to any model name. Strata also serves the
Anthropic Messages API (`/v1/messages`) and the Responses API (`/v1/responses`).

```python
from openai import OpenAI
client = OpenAI(base_url="https://llm.in.reinitialized.net/v1", api_key="<key>")
r = client.chat.completions.create(
    model="qwen3.8-flash-next",
    messages=[{"role": "user", "content": "Hello"}],
    reasoning_effort="low",
)
print(r.choices[0].message.content)  # reasoning is in message.reasoning_content
```

The context is 131072 tokens. A request alone decodes at about 33 tokens/s.
Two requests run at once, at about 18 tokens/s each while both decode with short
contexts (less with long ones; see Performance); a third waits. Strata reads prompts at about 145 tokens/s, so a 30k-token prompt takes
about 3.5 minutes. Use `stream=True` for long prompts: Strata sends an SSE
comment every 10 s while it reads, and the proxy inactivity timeout is 1 h.
Follow-up turns reuse checkpoints of the conversation (6 by default), and each
of the two batch slots keeps its last conversation.

## Reasoning effort

Strata takes `reasoning_effort` `none`, `low`, `medium`, or `high` (the default),
also as `reasoning.effort` or `chat_template_kwargs: {"enable_thinking": false}`.
Anthropic requests use `output_config.effort` or `thinking`.

## Web UI and agent tools

The web UI is at `https://llm.in.reinitialized.net/` from the
LAN and VPN (rp1 `internalOnly`), and at `http://127.0.0.1:8080` on llm1.
Strata's UI has Chat (with an off/low/medium/high thinking menu and **Use tools
from MCP servers** in the Sampling drawer), a live Monitor (tokens/s, expert
cache hits, GPU, CPU, RAM, MCP servers), and About; enter an API key under
About > Settings, which keeps it in the browser only.

`strata-tools.service` runs
every credential-free MCP server nixpkgs packages, plus `hosts/llm1/mcp-shell.py`
(nixpkgs has no shell server), behind `mcp-proxy` on `127.0.0.1:8097`:

| Server | Tools |
|--------|-------|
| `shell` | `run_command` (bash, up to 600 s) |
| `files` | read, write, edit, list, search, move (workspace only) |
| `git` | status, diff, add, commit, log, branch, ... |
| `fetch` | web page to markdown |
| `browser` | Playwright headless Chromium (21 tools) |
| `documents` | MarkItDown: PDF/Office/HTML/URL to markdown |
| `memory` | a knowledge graph kept in `memory.jsonl` |
| `thinking` | sequential thinking |
| `time` | current time, time zone conversion |
| `nixos` | NixOS packages and options search |
| `library-docs` | Context7 library documentation |

Strata's chat page calls them as `<server>__<tool>` (up to 64 calls per answer,
600 s per call, results cut at 40,000 characters); API clients opt in with
`"strata_mcp": true`.

The tools run as their own DynamicUser, not as Strata, so they
cannot read the API keys, Strata's pack, or the engine. Their workspace is
`/var/lib/private/strata-tools/workspace` (the shell starts there and the file
server allows only it; use that path, not the `/var/lib/strata-tools` symlink).
They have the system's tools on `PATH`, internet access, read-only system paths,
no home directories, no `/mnt`, `/srv`, `/media`, and no LAN or private ranges.
The tool listener has no authentication of its own and accepts loopback only.

What this exposes: anyone on the LAN or VPN with an API key can have the model
run commands, edit files, browse, and fetch from the internet as that user, and
text the model reads (a web page, a document) can steer what it runs. Strata
only runs MCP tools for requests from its own page or `trusted_origins`; another
site's page gets 403.

After `strata-tools` restarts, Strata's first call to each server fails once
and is retried on a new session; restart `strata` to avoid it.

## API keys

Keys live in `/var/lib/service-secrets/llm-api-keys` (root, `0600`), one per
line, and `#` lines are comments. Override the path with
`secrets.llmApi.file` in the external llm1 secret module. Strata reads the
file through `LoadCredential`, so restart it after an edit
(`sudo systemctl restart strata`). Use one key per consuming project so a key
can be revoked on its own. With no key file, or no key in it, the unit fails
closed.

Upstream Strata takes a single key. `hosts/llm1/strata-api-keys.patch` makes
it accept the one-key-per-line file and adds a test. The package build runs
Strata's security tests, including that one.

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

How it uses the hardware:

- All 61 GiB of routed experts are copied from the GGUF shards into RAM and
  pinned (`cudaHostRegister`), so the VM needs that much memory free. Loading
  takes 1-2 minutes from the page cache.
- The GPU holds the dense weights (2.2 GiB, 1.9 GiB of them read natively from
  the GGUF), the MTP draft layer (835 MiB), the most-read 20K positions of the KV
  cache (the rest streams from 1.55 GiB of pinned RAM), the two batch slots'
  state (2 x 0.58 GiB) and drafters, and an expert cache in the remaining VRAM:
  about 600 experts (1.48 GiB, about 2.4% of 24,576). The cache starts from what
  it learned before the last restart (`expert_profile_save`), or upstream's
  routing profile, and adapts to the requests.
- About 30% of routed experts are cache hits on the GPU. The CPU pool computes
  the rest at about 50 GB/s, close to the guest's measured 64 GB/s DRAM read
  limit, so the CPU's memory bandwidth bounds decode. `--pcie-frac 0` keeps
  missed experts off PCIe: copying them made the GPU wait longer than the CPU
  took.
- The MTP draft layer is the base model's (upstream recipe: `q2_0` experts, the
  English/code draft vocabulary to save VRAM). It drafts up to 4 tokens, and
  65-85% are accepted.

### One-time preparation

The unit starts only once these exist in `/var/lib/private/strata` (the unit's
`StateDirectory`; with `DynamicUser` systemd keeps it there and adds the
`/var/lib/strata` symlink only when the unit starts, so use the real path). Run
the tools as root from the package's tree (`strata` and `strata-python` are on
llm1's PATH):

```bash
S=$(dirname "$(dirname "$(readlink -f "$(command -v strata)")")")
cd $S/share/strata
# The dense pack (~1.4 GiB, under a minute). Experts and the PLE table stay in the GGUF.
sudo $S/bin/strata-python tools/iq_pack.py --compat-bf16 \
  --gguf /mnt/data/models/Qwen3.8-Flash-Next-Uncensored-IQ4_XS-00001-of-00003.gguf \
  --out /var/lib/private/strata/packs/orca-iq4_xs
# The base model's MTP tensors (~5 GB of HTTP range reads from Hugging Face), then the draft runtime.
sudo $S/bin/strata-python tools/mtp_fetch.py fetch --out /var/lib/private/strata/mtp
sudo $S/bin/strata-python tools/mtp_pack.py --src /var/lib/private/strata/mtp --experts q2_0 \
  --out /var/lib/private/strata/mtp/mtp-q2_0.gguf
sudo $S/bin/strata-python tools/mtp_rt.py --gguf /var/lib/private/strata/mtp/mtp-q2_0.gguf \
  --out /var/lib/private/strata/mtp/rt
sudo cp data/draft_vocab_en.bin /var/lib/private/strata/mtp/rt/draft_vocab.bin
```

The engine log is `/var/lib/strata/strata.log`; the server's progress lines go
to the journal. Upstream validates OrcaRouter IQ3_XXS and Q4_K_S. This IQ4_XS
file (IQ4_XS gate/up, IQ4_NL down experts) packs and runs with the same
`--compat-bf16` path, which rounds 364 small projections to BF16 (max abs error
0.022); the engine patch reads 192 of them, the hyper-connection projections,
from the GGUF instead. Answers were checked by hand, not with a quality
benchmark.

### Engine patch

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
  this card. `STRATA_BATCH_DRAFTS=0` restores one token per slot;
  `STRATA_BATCH_DRAFTS_N=1..3` sets the drafts per slot.
- **Pipelined batch windows.** With `--spec-split`, a window of two slots runs as
  two groups, one per slot. The CPU computes one slot's experts while the GPU
  runs the other's layers. A slot that is alone is split like a solo window.
- **The adaptive VRAM tier also adapts during batch windows.** Upstream adapts
  it only between solo windows.
- **Direct slot copies.** Moving a conversation between the main session and a
  slot copies its device state on the device and its K/V host copy once.
  Upstream goes through a host image, which takes about twice as long.
  `STRATA_DIRECT_COPY=0` restores that.
- **A single-token IQ4_XS gate/up kernel for the CPU pool.** It handles both rows
  in one pass with two sub-blocks per AVX2 register: 1.36x ggml-cpu's dot in
  isolation (relative difference 1e-7), and 10% less CPU time in batch windows,
  where most expert groups hold one token. `STRATA_IQ4XS_GU1=0` uses
  ggml-cpu's dot.

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

The llm1 row was measured on 2026-10-06 at 18:56 with the same client and
prompts (second of two passes), right after the move: llm1 matches devenv.

What each change gave (one request, mean t/s, earlier the same night with a
single pass): `--pcie-frac 0` 21.3 to 27.3 (the GPU had waited about 64 ms per
window for PCIe expert copies), `--spec-split` 31.5, and the engine patch 33.4.
Without the patch, two requests do not fit on the card at 131072 tokens (the
draft head runs out of VRAM); upstream's batch windows ran at 11-12 t/s per
request.

A batch window of two requests verifies about 8 rows (each request's token plus
3 drafts) and keeps 5.8 tokens in 160 ms, of which the CPU pool takes 124 ms.
That pass is bound by memory bandwidth: about 44 distinct experts per layer, read
at 46 GB/s, against the guest's measured 64 GB/s read limit. A request alone gets
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

Measured and not used:

| Change | Result |
|--------|--------|
| `--pool-workers 20` | batch windows 3.5% faster; one request unchanged; 7 more busy vCPUs |
| `--pool-workers 27` (no split) | 2% slower than 13 |
| `STRATA_BATCH_DRAFTS_N=2` | batch windows 135 ms but 4.6 tokens: 6% less throughput |
| 15% of a batch window's missed experts over PCIe (DMA) | 170 ms instead of 161: the copies take the same DRAM bandwidth |
| skipping the CPU experts of batch drafts under min-p | 10% less CPU time, 5% fewer tokens per window: break-even |
| `STRATA_FUSE_HEAD_GR=1`; a one-warp-per-row MMVQ kernel | within noise (+0.5%, +1.4%) |
| `--prefill 2048` with two slots | does not fit; falls back to 512-token chunks (95 t/s) |
| `STRATA_IQ4XS_GU1=0` (the patch's CPU kernel off) | batch CPU time 10% higher; one request -2% |

### Nightly backups

Strata reads the 28.8 GB n-gram (PLE) table with direct I/O from llm1's data
disk on hotData, 16 rows per token, prefetched as drafts are made. While hv1's
nightly vzdump runs (01:00, all VMs; a full read of a large disk can take hours),
those reads slow from about 0.15 ms to 0.5 ms typical and 80-800 ms at the 99th
percentile, and decode can fall to a third. A row the engine has read before is
cached in its 1M-row cache, so repeated text is not affected. `--ple-io ram`
avoids the disk entirely, but it locks 27 GiB more RAM; llm1 (104 GiB) would
keep about 16 GiB for the page cache and the system. Not tried.

### Host tuning not applied (needs operator approval on hv1)

These were measured or identified, but they are hv1 changes and were not made:

1. **Pin vCPUs 1:1.** Pin vCPU k to host CPU `2k+1` and vCPU k+14 to its sibling
   `2k+29`. This should steady Strata's pool workers. Proxmox `affinity` only pins the whole process, so
   this needs a hookscript.
2. **Raise the uncore floor on package 1.** Set
   `/sys/devices/system/cpu/intel_uncore_frequency/package_01_die_01/min_freq_khz`
   to `2700000`. It idles at 1.2 GHz under the BIOS DAPC profile.
3. **Limit C-states on node 1 only.** Set `pm_qos_resume_latency_us` on the odd
   CPUs, and/or enable KVM halt polling (`halt_poll_ns_grow` is 0). The BIOS
   `PerfPerWattOptimizedDapc` profile needs a reboot to change.
4. **More memory bandwidth.** Decode is bound by node 1's DRAM bandwidth (the
   CPU pool reads experts at 46-53 GB/s). Memory and vCPUs on both nodes, with
   the expert arena interleaved, could raise it. This is untested: node 0's
   memory reaches the GPU and node-1 cores over QPI.
5. **Backup-proof n-gram reads.** Either restore hotData's mirror (the pool lost
   an NVMe to the GPU) or use `--ple-io ram` on llm1.

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
  `strata-tools` and everything else restart normally.

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
numa 1, numa0 cpus=0-27,hostnodes=1,memory=106496,policy=bind
affinity 1,3,5,...,55 (the odd CPUs, node 1)
hostpci0 0000:82:00,pcie=1
hotplug disk,network,usb (no memory hotplug: DIMM backends get no host-nodes)
allow-ksm 0, onboot 1, startup order=4, iothread=1 on scsi0 and scsi1
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
- Strata is pinned to `6f32ec0` (engine 0.1.39). When bumping it, update the
  ggml commit from `third_party/ggml/VERSION.txt`, re-check the API key patch,
  and rebase `strata-performance.patch` (verifier, MTP drafter, batch loop, and
  CPU/GPU kernels), then re-run upstream's `tools/batch_test.py`.
