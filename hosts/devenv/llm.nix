# Qwen3.8-Flash-Next behind one OpenAI-compatible API: Strata on the GTX 1070,
# with MCP agent tools.
# Operations, preparation, and tuning evidence: docs/devenv-llm.md
{
  config,
  lib,
  pkgs,
  ...
}:
let
  modelDir = "/home/develop/llm-trial/models";
  model = "${modelDir}/Qwen3.8-Flash-Next-Uncensored-IQ4_XS-00001-of-00003.gguf";
  port = 8080;
  meshPort = 1045;

  llmSecret = config.secrets.llmApi or { };
  apiKeyFile =
    if llmSecret ? file && llmSecret.file != null then
      toString llmSecret.file
    else
      "/var/lib/service-secrets/llm-api-keys";

  # Strata serves the model with the most-used experts on the GTX 1070. Its
  # pack and MTP draft layer are prepared once into strataDir (docs/devenv-llm.md).
  strata = pkgs.callPackage ./strata.nix { };
  strataDir = "/var/lib/strata";
  strataConfig = pkgs.writeText "strata.json" (
    builtins.toJSON {
      exe = "${strata}/bin/strata";
      args = [
        "--pack"
        "${strataDir}/packs/orca-iq4_xs"
        "--native"
        model
        "--ple-gguf"
        model
        "--expert-profile"
        "${strata}/share/strata/data/expert-profile.bin"
        "--expert-cache"
        "auto"
        "--prefill"
        "auto"
        "--spec"
        "4"
        "--spec-min-p"
        "0.5"
        "--mtp"
        "${strataDir}/mtp/rt"
        # Missed experts run on the CPU only: the GPU otherwise waited on their
        # PCIe copies. Split windows overlap the CPU's experts with the GPU.
        "--pcie-frac"
        "0"
        "--spec-split"
        # Streaming the KV cache from pinned RAM keeps 20K cells per layer in
        # VRAM (the minimum), which leaves room for the second request's state.
        "--max-context"
        "131072"
        "--kv"
        "int8"
        "--kv-resident"
        "20480"
        # One worker per physical core (the guest sees 28 cores, really 14 with
        # hyperthreads) leaves half the vCPUs free; 20 or 27 workers were no
        # faster for one request (batch windows: 3.5% with 20).
        "--pool-workers"
        "13"
      ];
      # Two requests decode together (strata-performance.patch gives each its
      # MTP drafts); a request alone runs on the faster single-request path.
      parallel = 2;
      # Start from what the VRAM expert cache learned before the last restart.
      expert_profile_save = "expert-profile-learned.bin";
      cwd = strataDir;
      tokenizer = "${strataDir}/packs/orca-iq4_xs/tokenizer";
      model_name = "qwen3.8-flash-next";
      log = "${strataDir}/strata.log";
      host = "127.0.0.1";
      # The page is also served as https://llm.in.reinitialized.net through rp1;
      # Strata only runs MCP tools for requests from its own page.
      trusted_origins = [ "https://llm.in.reinitialized.net" ];
      mcp_servers = lib.mapAttrs (name: _: { url = toolUrl name; }) toolServers;
      mcp = {
        timeout_s = 600;
        max_rounds = 64;
        max_result_chars = 40000;
      };
    }
  );

  # Agent tools (MCP servers) for Strata, run by strata-tools.service
  # as their own sandboxed user: they cannot read the API keys, the pack, or the
  # engine. Every credential-free server nixpkgs has, plus a shell (mcp-shell.py).
  toolsDir = "/var/lib/strata-tools";
  toolsPort = 8097;
  toolUrl = name: "http://127.0.0.1:${toString toolsPort}/servers/${name}/mcp";
  toolServers = {
    shell = {
      command = "${pkgs.python3}/bin/python3";
      args = [ "${./mcp-shell.py}" ];
    };
    files = {
      command = "${pkgs.mcp-server-filesystem}/bin/mcp-server-filesystem";
      # The resolved path: the server refuses paths through the DynamicUser
      # symlink (/var/lib/strata-tools -> private/strata-tools).
      args = [ "/var/lib/private/strata-tools/workspace" ];
    };
    git.command = "${pkgs.mcp-server-git}/bin/mcp-server-git";
    fetch.command = "${pkgs.mcp-server-fetch}/bin/mcp-server-fetch";
    browser = {
      command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
      args = [
        "--headless"
        "--isolated"
        "--output-dir"
        "${toolsDir}/workspace/browser"
      ];
    };
    documents.command = "${pkgs.markitdown-mcp}/bin/markitdown-mcp";
    memory.command = "${pkgs.mcp-server-memory}/bin/mcp-server-memory";
    thinking.command = "${pkgs.mcp-server-sequential-thinking}/bin/mcp-server-sequential-thinking";
    time.command = "${pkgs.mcp-server-time}/bin/mcp-server-time";
    nixos.command = "${pkgs.mcp-nixos}/bin/mcp-nixos";
    library-docs.command = "${pkgs.context7-mcp}/bin/context7-mcp";
  };
  toolsConfig = pkgs.writeText "strata-tools.json" (builtins.toJSON { mcpServers = toolServers; });
in
{
  # GTX 1070 (Pascal, passed through from hv1). Same driver setup as ai1: Pascal
  # support ends with the 580 branch and needs the closed kernel module.
  nixpkgs.config = {
    allowUnfree = true;
    cudaCapabilities = [ "6.1" ];
    cudaForwardCompat = false;
  };
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware = {
    graphics.enable = true;
    nvidia = {
      branch = "legacy_580";
      open = false;
      gsp.enable = false;
      modesetting.enable = false;
      nvidiaPersistenced = true;
      nvidiaSettings = false;
      powerManagement.enable = false;
      videoAcceleration = false;
    };
  };
  boot.kernelModules = [ "nvidia" ];
  # strata-python runs the one-time packers (docs/devenv-llm.md).
  environment.systemPackages = [ strata ];

  systemd.services.strata = {
    description = "Strata: Qwen3.8-Flash-Next on the GTX 1070";
    wantedBy = [ "multi-user.target" ];
    after = [
      "nvidia-persistenced.service"
      "strata-tools.service"
    ];
    wants = [ "strata-tools.service" ];
    unitConfig.ConditionPathExists = [
      modelDir
      "${strataDir}/packs/orca-iq4_xs"
      "${strataDir}/mtp/rt"
    ];
    # The web UI's Monitor loads NVML (libnvidia-ml.so.1) by name.
    environment.LD_LIBRARY_PATH = "/run/opengl-driver/lib";
    script = ''
      # Fail closed: an empty key file would start the server without authentication.
      grep -qv '^[[:space:]]*\(#.*\)\?$' "$CREDENTIALS_DIRECTORY/api-keys" ||
        { echo "no API key in $CREDENTIALS_DIRECTORY/api-keys" >&2; exit 1; }
      STRATA_API_KEY=$(cat "$CREDENTIALS_DIRECTORY/api-keys") \
        exec ${strata}/bin/strata-server --engine strata --config ${strataConfig} --port ${toString port}
    '';
    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "strata";
      LoadCredential = "api-keys:${apiKeyFile}";
      ProtectHome = "tmpfs";
      BindReadOnlyPaths = [ modelDir ];
      DevicePolicy = "closed";
      DeviceAllow = [
        "/dev/nvidiactl rw"
        "/dev/nvidia0 rw"
        "/dev/nvidia-uvm rw"
        "/dev/nvidia-uvm-tools rw"
      ];
      # Tools run in strata-tools, not here: loopback only.
      IPAddressAllow = "localhost";
      IPAddressDeny = "any";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      LockPersonality = true;
      Nice = -5;
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  systemd.services.strata-tools = {
    description = "MCP agent tools for Strata";
    # Tools run commands: give them the system's tools.
    path = [ config.system.path ];
    environment = {
      HOME = toolsDir;
      MEMORY_FILE_PATH = "${toolsDir}/memory.jsonl";
    };
    serviceConfig = {
      ExecStart = "${pkgs.mcp-proxy}/bin/mcp-proxy --host 127.0.0.1 --port ${toString toolsPort} --pass-environment --named-server-config ${toolsConfig}";
      DynamicUser = true;
      StateDirectory = [
        "strata-tools"
        "strata-tools/workspace"
      ];
      # Named servers inherit this; the shell starts in the workspace.
      WorkingDirectory = "${toolsDir}/workspace";
      ProtectHome = "tmpfs";
      PrivateDevices = true;
      TemporaryFileSystem = [
        "/srv:ro"
        "/mnt:ro"
        "/media:ro"
      ];
      # Internet for fetch, docs, and the browser; loopback for Strata;
      # no LAN or private ranges. The listener is loopback-only (no auth in
      # mcp-proxy): reaching it needs code already running on devenv.
      IPAddressDeny = [
        "10.0.0.0/8"
        "172.16.0.0/12"
        "192.168.0.0/16"
        "100.64.0.0/10"
        "169.254.0.0/16"
        "fc00::/7"
        "fe80::/10"
      ];
      # No RestrictNamespaces: the browser's own sandbox uses user namespaces.
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      LockPersonality = true;
      Restart = "on-failure";
      RestartSec = "5s";
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
