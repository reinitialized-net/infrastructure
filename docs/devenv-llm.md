# devenv LLM Service (Qwen3.8-Flash-Next)

`hosts/devenv/llm.nix` runs llama.cpp's `llama-server` as `llama-cpp.service` on
devenv. It serves Qwen3.8-Flash-Next-Uncensored (IQ4_XS, about 97 GB in three
GGUF shards) on CPU, with the model's MTP head for speculative decoding.

## Endpoints

| Client location | Base URL | Notes |
|-----------------|----------|-------|
| LAN / VPN | `https://llm.in.reinitialized.net/v1` | rp1, ACME TLS, `internalOnly`, only `/v1/` proxied |
| Mesh hosts | `http://10.255.0.1:1045/v1` | `llm-api-mesh.socket` forwards to loopback; WireGuard-encrypted |
| devenv itself | `http://127.0.0.1:8080/v1` | Also serves the agent web UI |

Every route except `/health`, `/v1/health`, and the web UI's static files
requires `Authorization: Bearer <key>`. The OpenAI SDKs send it when you set
`api_key`. The model ID is `qwen3.8-flash-next` (`--alias`). Everything outside
`/v1/` on rp1 returns 404.

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

Use `stream=True` for long prompts. Prompt processing runs at about 22-28
tokens/s, so a cold 20k-token prompt takes over 12 minutes. The server sends
SSE pings every 30 s, and the proxy inactivity timeout is 1 h. Appended
conversations reuse the cached prefix. The single slot keeps up to 32
checkpoints at a minimum spacing of 8192 tokens, and an 8 GiB host prompt cache
holds idle conversations.

## Reasoning effort

The model's template has three levels: `low`, `medium`, and `xhigh`, with
`xhigh` as the default. `hosts/devenv/qwen38-chat-template.jinja` is the
model's template, with the OpenAI names mapped onto those levels:

| Request `reasoning_effort` | Model level |
|----------------------------|-------------|
| `none` | thinking disabled (`<think></think>` prefilled) |
| `minimal`, `low` | `low` |
| `medium` | `medium` |
| `high`, `xhigh`, `max`, omitted | `xhigh` |

The Responses API's `reasoning.effort` maps the same way.
`chat_template_kwargs: {"enable_thinking": false}` also disables thinking.
`thinking_budget_tokens: N` adds a hard cap on thinking tokens.

The upstream web UI's effort menu only sent a thinking-token budget (Low 512,
Medium 2048, High 8192), so the model was always told `xhigh` and then
truncated. `hosts/devenv/llama-ui-reasoning-effort.patch` makes the UI also send
`reasoning_effort`. Remove the patch once upstream sends it.

## Web UI and agent tools

The agent UI (`--agent`: built-in file/shell tools and the MCP CORS proxy) is
only on devenv loopback. Open it with
`ssh -L 8080:127.0.0.1:8080 devenv` (or VS Code port forwarding) at
`http://127.0.0.1:8080`, then enter an API key under Settings. Tools run as the
unit's DynamicUser, with no home directory, no LAN or private ranges, and
read-only system paths (`/var`, `/srv`, `/mnt`, `/media`, and `/run` hidden).
The rp1 route deliberately excludes `/tools` and the UI.

## API keys

Keys live in `/var/lib/service-secrets/llm-api-keys` (root, `0600`), one per
line, and `#` lines are comments. Override the path with
`secrets.llmApi.file` in the external devenv secret module. The unit reads the
file through `LoadCredential`, so after an edit run
`sudo systemctl restart llama-cpp`. Use one key per consuming project so a
key can be revoked on its own. With no key file, the unit fails closed.

## Performance

Measured on hv1 (2x E5-2690 v4) with devenv cut over to NUMA node 1: 28
vCPUs on 14 physical cores with hyperthreads, and 104 GiB bound to node 1.

| Configuration | Decode t/s | Notes |
|---------------|-----------:|-------|
| Trial (`-t 14 -tb 28 -ub 256`, mmap, no drafting) | 5.9-6.3 | server, 4 prompts; llama-bench tg64 6.74, pp512 28.3 |
| + MTP draft, `--spec-draft-n-max 3` | 7.55 | acceptance 49-81% |
| **+ MTP draft, `--spec-draft-n-max 2`** | **8.06** | code at T=0 9.1, prose 7.2-7.4 |
| MTP 4 with `--spec-draft-p-min 0.5` | 7.79 | |
| MTP 3 with `--spec-draft-p-min 0.6` | 6.39 | p-min suppresses useful drafts |
| MTP 2 with `-tb 14` | 8.10 | same as `-tb 28`, so 28 is kept for prompt processing |
| Deployed service (Nix build, warm) | 7.73 | 8.56 / 7.15 / 8.59 / 6.61; 7.16 on the first requests after a restart |

The sweep used a hand-built `-march=native` binary. Interleaved llama-bench
A/B runs compared it with the Nix package:

| Build | pp512 | tg64 |
|-------|------:|-----:|
| hand-built, `-march=native`, no hardening | 28.3-28.8 | 7.24-7.28 |
| nixpkgs default (dynamic CPU variants, haswell picked) | 26.9-27.2 | 6.87-6.88 |
| **deployed: single variant, `-march=broadwell -mtune=broadwell`** | 27.5-28.0 | 6.93-6.94 |

The remaining ~4.5% decode gap matches Nix's default compiler hardening: the
hot kernels zero registers on every return (`zerocallusedregs`) and build with
`-fno-strict-overflow`. Disabling those flags for this package should close the
gap, but it trades away hardening. It was not applied without explicit approval.

These changes made no measurable difference within the ±7% run-to-run noise:
hugepages for all hot weights (`-lm none` plus `glibc.malloc.hugetlb=1`, 67 GB
verified on THP) and `-lzm off`. An earlier MTP attempt reached 0.33 t/s only
because the VM was thrashing. The draft head and the mmap+repack double
residency overflowed RAM, so even prompt processing collapsed to 1.5 t/s.
`--lazy-mode auto` without mlock leaves enough headroom.

A decode profile (perf, 6.43 t/s) breaks down as follows:

- 53% quantized matmul kernels, running at about 46 GB/s effective (near node
  1's memory bandwidth)
- 32% OpenMP barrier spin (`gomp_team_barrier_wait_end`), waiting on
  straggler threads
- 14% small ops

The barrier share comes from unpinned vCPUs. The guest's 14 decode threads can
land on hyperthread siblings or share a core with host work. Each token reads
about 3.8 GiB, of which 2.6 GiB is dense. That is why the GPU plan below
targets the dense part.

### Host tuning not applied (needs operator approval on hv1)

These were measured or identified, but they are hv1 changes and were not made:

1. **Pin vCPUs 1:1.** Pin vCPU k to host CPU `2k+1` and vCPU k+14 to its sibling
   `2k+29`. Then bind the 14 decode threads to vCPUs 0-13 with
   `OMP_PLACES=cores OMP_PROC_BIND=close`. This targets the 32% barrier wait,
   and is the largest remaining CPU-side gain. Proxmox `affinity` only pins the
   whole process, so this needs a hookscript.
2. **Raise the uncore floor on package 1.** Set
   `/sys/devices/system/cpu/intel_uncore_frequency/package_01_die_01/min_freq_khz`
   to `2700000`. It idles at 1.2 GHz under the BIOS DAPC profile.
3. **Limit C-states on node 1 only.** Set `pm_qos_resume_latency_us` on the odd
   CPUs, and/or enable KVM halt polling (`halt_poll_ns_grow` is 0). The
   2026-10-05 storage investigation measured small gains for model loading
   from both. The BIOS `PerfPerWattOptimizedDapc` profile needs a reboot to
   change.

## GTX 1070 plan

The planned GPU goes in R730 slot 4, which is on CPU2, the same NUMA node as
devenv. That slot currently holds a hotData mirror NVMe, which moves to slots
1-3 first.

1. Pass the GPU through to VM 202. Add `nixpkgs.config` `allowUnfree`,
   `cudaCapabilities = [ "6.1" ]` and `cudaForwardCompat = false`, and set
   `hardware.nvidia.branch = "legacy_580"` (the last branch with Pascal), as
   `hosts/ai1.nix` does.
2. Build with `pkgsUnstable.llama-cpp.override { cudaSupport = true;
   cudaPackages = pkgsUnstable.cudaPackages_12_9; blasSupport = false; }`.
   CUDA 13 dropped Pascal.
3. In `llm.nix`, set `PrivateDevices = false` and add `DeviceAllow` for
   `/dev/nvidia*`. Add `--n-gpu-layers 99`, keep experts in RAM with
   `--cpu-moe` (or `--n-cpu-moe N` to put a few expert layers in leftover
   VRAM), and offload the MTP head with `-ngld 99`.

The dense weights, about 2.6 GiB of the 3.8 GiB read per token, plus the
KV cache fit in 8 GiB. The CPU then streams only the roughly 1.2 GiB of routed
experts per token, and the GPU takes over prompt processing.

## Notes

- The model and MTP files stay in `/home/develop/llm-trial/models`, bind-mounted
  read-only. The trial scripts in `~/llm-trial` are superseded but still useful
  for llama-bench runs. Stop the service first: the VM cannot hold two copies.
- The live VM size (104 GiB, 28 vCPUs, node-1 binding) was a manual cutover on
  hv1. `flake.nix` still describes devenv as 64 GB with 6 cores. The original
  config is `/root/202.conf.pre-llm` on hv1.
- llama.cpp is pinned to `d89651a` because nixpkgs releases predate the
  qwen4exp tuning. Bump `rev`, `hash`, and `npmDepsHash` together, and re-check
  that the UI patch still applies.
