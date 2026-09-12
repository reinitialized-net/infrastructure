{ lib, pkgs, ... }:
let
  modelPath = "/var/lib/llama-cpp/models/model.gguf";

  # Pascal support ends after CUDA 12.9. Build only the GTX 1070's sm_61
  # kernels and target the i7-8700's Skylake-compatible CPU instruction set.
  llamaCppPascal =
    (pkgs.llama-cpp.override {
      cudaSupport = true;
      cudaPackages = pkgs.cudaPackages_12_9;
    }).overrideAttrs
      {
        NIX_CFLAGS_COMPILE = "-march=skylake -mtune=skylake";
      };
in
{
  networking = {
    hostName = "ai1";
    useDHCP = false;
    firewall.allowlist = [
      {
        port = 8080;
        protocol = "tcp";
        ipType = "ipv4";
        # The llama.cpp API has no application authentication. Restrict it to
        # the operator desktop instead of every RFC1918 client.
        source = [ "10.1.13.10/32" ];
      }
    ];
  };

  systemd.network.networks."10-lan" = {
    matchConfig.Name = "en*";
    address = [ "10.1.13.10/24" ];
    dns = [
      "10.1.11.2"
      "10.1.11.3"
    ];
    ntp = [ "10.1.11.1" ];
    gateway = [ "10.1.13.1" ];
    linkConfig.RequiredForOnline = "routable";
  };

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

  boot = {
    kernelModules = [ "nvidia" ];
    kernelParams = [ "transparent_hugepage=madvise" ];
    kernel.sysctl."vm.swappiness" = 5;
  };

  powerManagement.cpuFreqGovernor = "performance";
  services = {
    irqbalance.enable = true;
    thermald.enable = true;
    llama-cpp = {
      enable = true;
      package = llamaCppPascal;
      model = modelPath;
      host = "0.0.0.0";
      port = 8080;
      extraFlags = [
        "--ctx-size"
        "131072"
        # llama-server divides the total context between slots. One slot is
        # required to preserve the full 128 Ki-token request window.
        "--parallel"
        "1"
        "--flash-attn"
        "on"
        # A 128 Ki-token F16 KV cache cannot fit on an 8 GiB GTX 1070.
        "--cache-type-k"
        "q4_0"
        "--cache-type-v"
        "q4_0"
        "--batch-size"
        "2048"
        "--ubatch-size"
        "512"
        "--threads"
        "6"
        "--threads-batch"
        "12"
        # Fit the maximum number of layers in VRAM while keeping the explicit
        # context and batch sizes unchanged.
        "--fit"
        "on"
        "--fit-target"
        "512"
        "--mlock"
        "--cache-reuse"
        "256"
        "--timeout"
        "3600"
        "--poll"
        "100"
        "--metrics"
        "--no-ui"
      ];
    };
  };

  systemd = {
    services.llama-cpp = {
      after = [ "nvidia-persistenced.service" ];
      wants = [ "nvidia-persistenced.service" ];
      unitConfig.ConditionPathExists = modelPath;
      environment = {
        CUDA_DEVICE_ORDER = "PCI_BUS_ID";
        CUDA_MODULE_LOADING = "EAGER";
      };
      serviceConfig = {
        LimitMEMLOCK = "infinity";
        MemorySwapMax = 0;
        Nice = -10;
        OOMScoreAdjust = -900;
        RestartSec = lib.mkForce "2s";
      };
    };
    targets = {
      sleep.enable = false;
      suspend.enable = false;
      hibernate.enable = false;
      hybrid-sleep.enable = false;
    };
    tmpfiles.rules = [
      "d /var/lib/llama-cpp/models 0755 root root -"
    ];
  };

  environment.systemPackages = [
    llamaCppPascal
    pkgs.btop
    pkgs.lm_sensors
    pkgs.nvtopPackages.nvidia
    pkgs.pciutils
  ];
}
