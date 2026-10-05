# Qwen3.8-Flash-Next (CPU) through llama.cpp's OpenAI-compatible server.
# Operations, tuning evidence, and GPU plan: docs/devenv-llm.md
{
  config,
  lib,
  pkgsUnstable,
  ...
}:
let
  modelDir = "/home/develop/llm-trial/models";
  port = 8080;
  meshPort = 1045;

  llmSecret = config.secrets.llmApi or { };
  apiKeyFile =
    if llmSecret ? file && llmSecret.file != null then
      toString llmSecret.file
    else
      "/var/lib/service-secrets/llm-api-keys";

  # qwen4exp needs a newer llama.cpp than either nixpkgs release; pin the commit the
  # tuning was measured on. BLAS off matches the measured build (ggml's own kernels).
  llamaCpp =
    (pkgsUnstable.llama-cpp.override {
      blasSupport = false;
      cpuArchDynamicDispatch = false;
    }).overrideAttrs
      (old: {
        version = "0.4.1-unstable-2026-10-05";
        src = pkgsUnstable.fetchFromGitHub {
          owner = "ggml-org";
          repo = "llama.cpp";
          rev = "d89651a7b205c03c4a0b13cd0646d400dc929f79";
          hash = "sha256-6ZrGg3/fR+cKMadcmQoP/tHPXjsaUPCiFcveBJOWY8A=";
        };
        # The UI only sent a thinking token budget; also send the effort level.
        patches = [ ./llama-ui-reasoning-effort.patch ];
        npmDepsHash = "sha256-a17M+L3nLdRnN6WMB6imPFmwqG2g8uv+gwN0XTAUrf8=";
        cmakeFlags = old.cmakeFlags ++ [ (lib.cmakeFeature "LLAMA_BUILD_COMMIT" "d89651a") ];
        # hv1's E5-2690 v4 (`cpu: host`). The generic-tuned haswell variant of the
        # default dynamic-dispatch build measured ~5% slower in decode and prompt.
        env = old.env or { } // {
          NIX_CFLAGS_COMPILE = "-march=broadwell -mtune=broadwell";
        };
      });
in
{
  services.llama-cpp = {
    enable = true;
    package = llamaCpp;
    model = "${modelDir}/Qwen3.8-Flash-Next-Uncensored-IQ4_XS-00001-of-00003.gguf";
    # Loopback only: agent tools (/tools) must not be network reachable. The mesh
    # listener below forwards here, and every route except /health needs an API key.
    host = "127.0.0.1";
    inherit port;
    extraFlags = [
      # Model ID for OpenAI clients (otherwise the GGUF path).
      "--alias"
      "qwen3.8-flash-next"
      # Decode is bandwidth/barrier bound: one thread per physical core of the
      # 14-core NUMA node is fastest; prompt processing gains from the hyperthreads.
      "--threads"
      "14"
      "--threads-batch"
      "28"
      "--ctx-size"
      "131072"
      "--parallel"
      "1"
      "--flash-attn"
      "on"
      "--batch-size"
      "2048"
      "--ubatch-size"
      "256"
      # mmap without mlock; lazy mode keeps the 26.8 GiB n-gram embedding table on
      # disk and pages hot rows in, leaving room for the MTP head and prompt cache.
      "--load-mode"
      "mmap"
      "--lazy-mode"
      "auto"
      # MTP draft head: 2 tokens measured fastest (+30% decode vs no drafting).
      "--spec-type"
      "draft-mtp"
      "--spec-draft-model"
      "${modelDir}/mtp-Qwen3.8-Flash-Next-Q8_0.gguf"
      "--spec-draft-n-max"
      "2"
      # Model template plus OpenAI-style reasoning_effort aliases.
      "--chat-template-file"
      "${./qwen38-chat-template.jinja}"
      "--api-key-file"
      "/run/credentials/llama-cpp.service/api-keys"
      # Cold long prompts take minutes on CPU; streamed requests get SSE pings.
      "--timeout"
      "3600"
      "--agent"
    ];
  };

  systemd.services.llama-cpp = {
    unitConfig.ConditionPathExists = modelDir;
    # Agent tools run as this unit's DynamicUser, so keep the trial's sandbox:
    # no home, LAN, or service state; system tools on PATH via the store path.
    path = [ config.system.path ];
    environment.HOME = "/var/lib/llama-cpp";
    serviceConfig = {
      LoadCredential = "api-keys:${apiKeyFile}";
      ProtectHome = lib.mkForce "tmpfs";
      BindReadOnlyPaths = [ modelDir ];
      TemporaryFileSystem = [
        "/var:ro"
        "/srv:ro"
        "/mnt:ro"
        "/media:ro"
        "/run:ro"
      ];
      # Flip to false with a DeviceAllow list once the GTX 1070 is passed through.
      PrivateDevices = lib.mkForce true;
      IPAddressDeny = [
        "10.0.0.0/8"
        "172.16.0.0/12"
        "192.168.0.0/16"
        "100.64.0.0/10"
        "169.254.0.0/16"
        "fc00::/7"
        "fe80::/10"
      ];
      # Agent shell tools may run JIT runtimes (node), as in the trial sandbox.
      MemoryDenyWriteExecute = lib.mkForce false;
      Nice = -5;
      RestartSec = lib.mkForce "10s";
    };
  };

  # Mesh clients and rp1 (llm.in.reinitialized.net) reach the API through a plain
  # TCP forwarder, so the server's LAN deny above stays intact.
  systemd.sockets.llm-api-mesh = {
    wantedBy = [ "sockets.target" ];
    listenStreams = [ "10.255.0.1:${toString meshPort}" ];
    socketConfig.FreeBind = true;
  };
  systemd.services.llm-api-mesh.serviceConfig = {
    ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${toString port}";
    DynamicUser = true;
  };
}
