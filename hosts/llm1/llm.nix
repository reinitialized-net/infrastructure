# Qwen3.8-Flash-Next behind one OpenAI-compatible API and Strata's web UI on the
# GTX 1070, with an isolated read-only web research service.
# Operations, preparation, and tuning evidence: docs/llm1.md
{
  config,
  pkgs,
  self,
  system,
  ...
}:
let
  modelDir = "/mnt/data/models";
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
  # pack and MTP draft layer (the fine-tune's own head) are prepared once into
  # strataDir (docs/llm1.md).
  # Built from nixpkgsStrata, a fixed nixpkgs that nightly updates never move
  # (docs/llm1.md, "Update policy").
  pkgsStrata = import self.inputs.nixpkgsStrata {
    inherit system;
    config = {
      allowUnfree = true;
      cudaCapabilities = [ "6.1" ];
      cudaForwardCompat = false;
    };
  };
  strata = pkgsStrata.callPackage ./strata.nix { };
  # The harness can evolve without recompiling or retuning the pinned GPU engine.
  harness = pkgs.runCommand "strata-harness" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
    mkdir -p $out/share/strata $out/bin
    cp -r ${strata}/share/strata/serve $out/share/strata/
    chmod -R u+w $out/share/strata/serve
    ln -s ${strata}/share/strata/tools $out/share/strata/tools
    ln -s ${strata}/share/strata/data $out/share/strata/data
    cp ${./harness/test_workspace.py} $out/share/strata/serve/test_workspace.py
    cp ${./harness/workspace_proxy.py} $out/share/strata/serve/workspace_proxy.py
    cp ${./harness/workspace.js} $out/share/strata/serve/web/workspace.js
    cp ${./harness/workspace.css} $out/share/strata/serve/web/workspace.css
    cd $out/share/strata
    ${pkgs.python3}/bin/python3 ${./harness/install.py}
    makeWrapper ${strata}/bin/strata-python $out/bin/strata-server \
      --chdir $out/share/strata --add-flags "-m serve.server"
    PYTHONDONTWRITEBYTECODE=1 ${strata}/bin/strata-python -m unittest serve.test_security serve.test_workspace
  '';
  analysisPython = pkgs.python3.withPackages (p: [
    p.numpy
    p.pandas
    p.matplotlib
    p.pypdf
    p.python-docx
    p.openpyxl
  ]);
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
        "${strataDir}/mtp-orca/rt"
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
        # Each batch slot also verifies an MTP draft per window.
        "--batch-mtp"
      ];
      # Two requests decode together; a request that starts alone runs on the
      # faster single-request path.
      parallel = 2;
      # Agents: while one prompt is read, the other slot decodes for as long as
      # each prompt chunk took (half the time instead of a third).
      env = {
        STRATA_BATCH_DECODE_SHARE = "1.0";
        # The adaptive VRAM tier's copies land layer by layer while the next window runs instead of the window
        # waiting for the whole round: one request 36.5 instead of 35.1 t/s (2026-10-13).
        STRATA_ADAPT_OVERLAP = "1";
        # Pascal has no tensor cores: use SGEMM for the supported large prompt
        # projections. gemm_f32_parity --quick passed on this GTX 1070 with
        # the pinned CUDA 12.9 cuBLAS (134 shapes, bitwise; 2026-10-13).
        STRATA_DENSE_F32 = "1";
      };
      # Start from what the VRAM expert cache learned before the last restart.
      expert_profile_save = "expert-profile-learned.bin";
      cwd = strataDir;
      tokenizer = "${strataDir}/packs/orca-iq4_xs/tokenizer";
      model_name = "qwen3.8-flash-next";
      log = "${strataDir}/strata.log";
      host = "127.0.0.1";
      trusted_origins = [ "https://llm.in.reinitialized.net" ];
      mcp_servers.web.url = "http://127.0.0.1:8091/mcp";
      mcp_servers.analysis.url = "http://127.0.0.1:8092/mcp";
      mcp = {
        timeout_s = 90;
        max_result_chars = 24000;
        max_rounds = 12;
      };
    }
  );
in
{
  # GTX 1070 (Pascal, passed through from hv1): Pascal support ends with the
  # 580 branch and needs the closed kernel module.
  nixpkgs.config.allowUnfree = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware = {
    graphics.enable = true;
    nvidia = {
      # Held at this version (legacy_580's attributes when it was pinned); the
      # module is rebuilt for each new kernel. Bump on purpose: docs/llm1.md.
      package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
        version = "580.173.02";
        sha256_64bit = "sha256-jY65AB4FqaimY9PV0wT+tk7yhE7hhczf2VJ4aCD0bhs=";
        sha256_aarch64 = "sha256-1lvVYIfvTXjwSoCNp4g8NaWQHF/TfpXRUKdgLrqXqoA=";
        openSha256 = "sha256-lhloZdf6XbaAFTZBF1DxE0Nv9VC6obY8UPf0VyfVepE=";
        settingsSha256 = "sha256-dfdu/3tnwHUfP7WoeQFNOMalMlpmUWjeMDIOnu+yi8E=";
        persistencedSha256 = "sha256-j8YM1w231X+JIP3c3TpUNurEBumEu1stVjzFGWu1JXE=";
      };
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
  # On llm1's data disk (mountData.nix); the shards are copied in by hand (docs/llm1.md).
  systemd.tmpfiles.rules = [ "d ${modelDir} 0755 root root -" ];
  # strata-python runs the one-time packers (docs/llm1.md).
  environment.systemPackages = [ strata ];

  systemd.services.strata = {
    description = "Strata: Qwen3.8-Flash-Next on the GTX 1070";
    wantedBy = [ "multi-user.target" ];
    after = [
      "nvidia-persistenced.service"
      "strata-web.service"
      "strata-analysis.service"
    ];
    wants = [
      "strata-web.service"
      "strata-analysis.service"
    ];
    # A nightly switch must not reload the model or cut open requests; the
    # pinned engine only changes on purpose (docs/llm1.md, "Update policy").
    restartIfChanged = false;
    # The real paths: systemd only creates the /var/lib/strata symlink when the
    # unit starts, so a condition on it never passes on a fresh host.
    unitConfig.ConditionPathExists = [
      modelDir
      "/var/lib/private/strata/packs/orca-iq4_xs"
      "/var/lib/private/strata/mtp-orca/rt"
    ];
    # VRAM checks load NVML (libnvidia-ml.so.1) by name.
    environment = {
      LD_LIBRARY_PATH = "/run/opengl-driver/lib";
      # Read by the server, not the engine: a request left alone stays in its
      # slot, since moving back to the solo path could lose its cached state.
      STRATA_PARALLEL_SOLO = "0";
    };
    script = ''
      # Strata takes several keys separated by commas; the file has one per line.
      keys=$(grep -v '^[[:space:]]*\(#.*\)\?$' "$CREDENTIALS_DIRECTORY/api-keys" | paste -sd,)
      # Fail closed: an empty key file would start the server without authentication.
      [ -n "$keys" ] || { echo "no API key in $CREDENTIALS_DIRECTORY/api-keys" >&2; exit 1; }
      STRATA_API_KEY=$keys \
        exec ${harness}/bin/strata-server --engine strata --config ${strataConfig} --port ${toString port}
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
      # Loopback only: mesh clients come in through llm-api-mesh.
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

  # Network access belongs to a separate user with no model state or API credentials.
  systemd.services.strata-web = {
    description = "Read-only web research tools for Strata";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${./web-tools.py}";
      DynamicUser = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
      MemoryMax = "256M";
      TasksMax = 32;
      Restart = "on-failure";
    };
  };

  systemd.services.strata-analysis = {
    description = "Isolated Strata document and Python analysis workers";
    wantedBy = [ "multi-user.target" ];
    environment = {
      ANALYSIS_PYTHON = "${analysisPython}/bin/python3";
      ANALYSIS_BWRAP = "${pkgs.bubblewrap}/bin/bwrap";
      ANALYSIS_PRLIMIT = "${pkgs.util-linux}/bin/prlimit";
      ANALYSIS_ARTIFACTS = "/var/lib/strata-analysis";
    };
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${./harness/analysis-tools.py}";
      DynamicUser = true;
      StateDirectory = "strata-analysis";
      StateDirectoryMode = "0700";
      PrivateDevices = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      # bwrap needs user/PID/mount/network namespaces; the model service does not.
      RestrictNamespaces = [
        "user"
        "mnt"
        "pid"
        "net"
        "ipc"
        "uts"
        "cgroup"
      ];
      IPAddressAllow = "localhost";
      IPAddressDeny = "any";
      TemporaryFileSystem = "/tmp:rw,size=256M,mode=1777";
      MemoryMax = "2G";
      TasksMax = 64;
      CPUQuota = "200%";
      UMask = "0077";
      Restart = "on-failure";
    };
  };

  # Mesh clients and rp1 (llm.in.reinitialized.net) reach the API through a plain
  # TCP forwarder, so the server's LAN deny above stays intact.
  systemd.sockets.llm-api-mesh = {
    wantedBy = [ "sockets.target" ];
    listenStreams = [ "10.255.0.9:${toString meshPort}" ];
    socketConfig.FreeBind = true;
  };
  systemd.services.llm-api-mesh.restartIfChanged = false;
  systemd.services.llm-api-mesh.serviceConfig = {
    ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${toString port}";
    DynamicUser = true;
  };
}
