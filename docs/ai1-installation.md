# ai1 Workstation Installation

`ai1` is the physical Dell XPS 8930 LLM host:

- Intel Core i7-8700 (6 cores / 12 threads)
- NVIDIA GeForce GTX 1070 with 8 GiB VRAM (Pascal, CUDA capability `6.1`)
- 32 GiB RAM
- two approximately 256 GB disks
- static address `10.1.13.10/24`, gateway `10.1.13.1`

The flake exports the installed system as `nixosConfigurations.ai1` and a USB-bootable installer as `packages.x86_64-linux.ai1-installer`.

## Build The Installer ISO

From the repository on `devenv`:

```bash
nix build path:.#ai1-installer
ls -lh result/iso/nixos-ai1-installer.iso
```

The ISO contains the complete `ai1` system closure, including the NVIDIA driver and the CUDA-enabled llama.cpp server. The workstation does not need network access during installation.

## Write The USB

Identify the USB device, not one of the workstation disks:

```bash
lsblk -d -o NAME,SIZE,MODEL,SERIAL
```

Write the ISO to the whole USB device. Replace `/dev/disk/by-id/usb-EXAMPLE` only after verifying it:

```bash
sudo dd \
  if=result/iso/nixos-ai1-installer.iso \
  of=/dev/disk/by-id/usb-EXAMPLE \
  bs=4M status=progress conv=fsync
```

This overwrites the selected USB device.

## Firmware Setup

Before booting the USB:

1. Use UEFI boot mode.
2. Disable Secure Boot; this configuration does not sign its boot artifacts.
3. Set storage/SATA mode to AHCI rather than Intel RST/RAID so Linux sees both disks directly.
4. Use wired Ethernet. The installed system intentionally has no desktop environment.

If the firmware can use the Intel integrated GPU for the console, doing so leaves the GTX 1070 dedicated to inference.

## Install

Boot the USB's UEFI entry. At the automatically logged-in `nixos` console, identify both internal disks:

```bash
lsblk -d -o NAME,SIZE,MODEL,SERIAL
```

Then run the installer with the OS disk first and model disk second. SATA disks commonly appear as `/dev/sda` and `/dev/sdb`; use the names actually shown on this machine:

```bash
sudo install-ai1 /dev/sda /dev/sdb
```

The command shows the selected disks and requires typing `ERASE ai1`. It then completely erases both disks and creates:

| Disk | Layout |
|------|--------|
| System disk | 1 GiB UEFI system partition (`BOOT`), then ext4 root (`nixos`) |
| Model disk | ext4 filesystem (`AI-MODELS`) mounted at `/var/lib/llama-cpp` |

The installed system creates a 32 GiB emergency swap file on the system disk. Models stay on the dedicated model disk.

After installation completes, remove the USB and reboot.

## First Boot And Verification

The static address is taken from the workstation screenshot. Confirm that `10.1.13.10` is reserved and unused before first boot.

From `devenv`:

```bash
ssh rnetadmin@10.1.13.10
```

On `ai1`, verify the accelerator:

```bash
nvidia-smi
```

No model is baked into the ISO. The llama.cpp service remains inactive until this path exists:

```bash
/var/lib/llama-cpp/models/model.gguf
```

Use a GGUF model whose metadata declares a native context of at least 131,072 tokens. A Llama 3.2 3B Instruct `Q4_K_M` GGUF is the throughput-first fit for this hardware; Llama 3.1 8B Instruct offers higher quality but must leave more layers in system RAM and is substantially slower. Copy the selected model from your workstation:

```bash
scp /path/to/model.gguf rnetadmin@10.1.13.10:/tmp/model.gguf
ssh rnetadmin@10.1.13.10 \
  'sudo install -m 0644 /tmp/model.gguf /var/lib/llama-cpp/models/model.gguf && sudo systemctl start llama-cpp'
```

Confirm that llama.cpp retained the full context and offloaded layers to CUDA:

```bash
systemctl status llama-cpp --no-pager
journalctl -u llama-cpp -b --no-pager | grep -E 'n_ctx|CUDA|offload'
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/v1/models
```

The service exposes llama.cpp's OpenAI-compatible API at `http://10.1.13.10:8080/v1`. The firewall restricts it to RFC1918 private networks. During inference, `nvidia-smi` should show `llama-server` using the GPU.

## Deploy Updates From devenv

Deploy `devenv` once so its generated fleet tools learn the new target, then deploy `ai1`:

```bash
rebuildHost devenv
rebuildHost ai1
```

While installation is pending, the topology sets `ai1.fleetDeployment = false`.
This excludes it from `updateInfra` and unattended SSH identity checks while
retaining its build outputs and explicit `rebuildHost ai1` command. After verifying
the installed machine and its SSH fingerprint through the physical console,
provision its known-host entry and set `fleetDeployment = true` in
`modules/profiles/meshNetwork/meshTopology.nix`. Rebuild `devenv` to include `ai1`
in subsequent fleet runs:

```bash
updateInfra
```

Builds run on `devenv` and are copied over SSH to `rnetadmin@10.1.13.10`; the workstation does not need a repository checkout.

## Performance Configuration

The host runs llama.cpp directly, without Ollama or another serving layer. It pins NVIDIA's `legacy_580` branch and builds llama.cpp against the last Pascal-capable toolkit, CUDA 12.9, for only `sm_61`. CPU code targets the i7-8700's Skylake-compatible instruction set.

The server reserves one 131,072-token slot. llama.cpp divides its total context among parallel slots, so increasing `--parallel` without multiplying `--ctx-size` would violate the 128 Ki-token minimum. The context covers prompt and generated tokens together, and the model itself must natively support that length.

The GTX 1070 has no tensor cores and only 8 GiB VRAM. Q4 K/V cache plus Flash Attention cuts a Llama-family 128 Ki-token KV cache to roughly one quarter of its F16 size. llama.cpp's memory fitter then offloads the maximum number of model layers while preserving the explicitly configured context and batch sizes, retaining a 512 MiB VRAM safety margin.

Prompt processing uses a 2,048-token logical batch, a 512-token physical batch, all 12 logical CPU threads, prompt-cache reuse, locked memory, and no service swap. Generation uses the six physical CPU cores. NVIDIA persistence mode, the CPU performance governor, IRQ balancing, high scheduler priority, polling, and disabled sleep targets remove avoidable latency. Q4 KV cache is the deliberate quality/performance tradeoff required to keep 128 Ki tokens practical on this GPU.
