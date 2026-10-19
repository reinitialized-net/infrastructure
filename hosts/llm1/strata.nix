# Strata (https://github.com/Niko1221/Strata): Qwen3.8-Flash-Next with the hot
# experts on the GPU and the rest on the CPU. Pascal (sm_61) only builds as the
# experimental CUDA 12 engine (docs/OLDER_GPUS.md upstream).
{
  lib,
  fetchFromGitHub,
  cmake,
  ninja,
  makeWrapper,
  python3,
  autoAddDriverRunpath,
  cudaPackages_12_9,
}:
let
  cuda = cudaPackages_12_9;
  # ggml from the llama.cpp commit Strata pins (third_party/ggml/VERSION.txt);
  # otherwise CMake would FetchContent it during the build.
  ggml = fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    rev = "3cf03257f219afbe7334045ff7c6a06ac68c627d";
    hash = "sha256-SRGoXa+4ACBCB3eaG9XFYhMN1i0FyPEy9Rrer+dFGYI=";
  };
  # The server and the one-time packers (iq_pack.py, mtp_*.py; gguf-py needs PyYAML) need these.
  python = python3.withPackages (
    p: with p; [
      jinja2
      regex
      numpy
      psutil
      pillow
      pyyaml
    ]
  );
in
cuda.backendStdenv.mkDerivation {
  pname = "strata";
  version = "0.1.44.1";

  src = fetchFromGitHub {
    owner = "Niko1221";
    repo = "Strata";
    rev = "v0.1.44.1";
    hash = "sha256-Jfo2uldtyXW8Y/wQxA7WcYwtmzCGAOaXgnlMSo7K9LE=";
  };

  patches = [
    # Upstream 94d189f: all-zero converter compression metadata is unspecified.
    ./strata-compression-placeholder.patch
    # mtp_fetch.py: STRATA_MTP_REPO picks the repo; HF_TOKEN authenticates gated ones.
    ./strata-mtp-fetch.patch
    # Engine changes for the GTX 1070 and two requests at once (docs/llm1.md, "Engine patch").
    ./strata-performance.patch
    # Reuse the IQ4_XS kernel's activation lane layout across rows, with exact qualification.
    ./strata-activation-reuse.patch
    # Preserve turn checkpoints when a request returns from a batch slot to solo decoding.
    ./strata-slot-checkpoints.patch
    # Opt-in AVX2 IQ4_NL nibble decode, checked by the existing CPU parity tool.
    ./strata-cpu-decode.patch
    # Opt-in lane-preserving IQ4_XS wide decode; extends iq_avx2_parity.
    ./strata-cpu-round2.patch
    # Opt-in fused native dequantization to FP32, preserving intermediate FP16 rounding.
    ./strata-prefill.patch
    # Opt-in direct MTP KV state transfers, checked by conversation_snapshot_test.
    ./strata-decode-round2.patch
    # Prompt planner: staged chunks need no streaming ring; keep the larger ring probe (STRATA_PREFILL_PLAN_STAGED=0).
    ./strata-prefill-planner.patch
    # Hand the prompt path the CPU pool under --batch, so prompts share experts with the CPU (STRATA_BATCH_PREFILL_SHARE=0).
    ./strata-batch-prompt-share.patch
    # CPU pool: gate/up tasks quantize their own rows, gate/up and down run as one batch (STRATA_POOL_FUSED=0, STRATA_POOL_TASK_QUANT=0).
    ./strata-pool-fused.patch
    # Leaner IQ4_NL down rows and vector scale decode for multi-token IQ4_XS gate/up (STRATA_IQ4NL_LEAN=0, STRATA_IQ4XS_SCALES8=0).
    ./strata-cpu-round3.patch
    # Batch slot sessions borrow the main session's RoPE table: +25 expert-cache slots (STRATA_SHARE_ROPE=0).
    ./strata-rope-share.patch
    # One-token IQ4_NL down rows in ggml's accumulation order, without its per-row call (STRATA_IQ4NL_ONE=0).
    ./strata-cpu-down1.patch
    # serve: a re-rendered next turn goes to the slot sharing its longest start, not the other agent's (STRATA_SLOT_COMMON=0).
    ./strata-slot-affinity.patch
  ];

  nativeBuildInputs = [
    cmake
    ninja
    makeWrapper
    cuda.cuda_nvcc
    autoAddDriverRunpath
  ];
  buildInputs = [
    cuda.cuda_cudart
    cuda.libcublas
    cuda.cuda_cccl
  ];

  cmakeFlags = [
    (lib.cmakeBool "STRATA_ENABLE_CUDA" true)
    (lib.cmakeBool "STRATA_EXPERIMENTAL_SM60" true)
    (lib.cmakeBool "STRATA_BUILD_TESTS" true)
    (lib.cmakeBool "STRATA_BUILD_CONVERSATION_TESTS" true)
    (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" "61")
    (lib.cmakeFeature "STRATA_GGML_DIR" "${ggml}")
  ];
  # Build only the engine and focused Pascal qualification tools, not the full suite.
  ninjaFlags = [
    "strata"
    "gguf_geometry_test"
    "gemm_f32_parity"
    "mmvq_il_parity"
    "dequant_wide_parity"
    "dequant_fused_parity"
    "iq4xs_gu1_parity"
    "iq_avx2_parity"
    "conversation_snapshot_test"
  ];

  # Strata forces GGML_NATIVE, which the Nix compiler wrapper strips; target
  # hv1's E5-2690 v4 (`cpu: host`) explicitly instead, as hosts/llm1/llm.nix does.
  env.NIX_CFLAGS_COMPILE = "-march=broadwell -mtune=broadwell";

  # The engine, plus the Python server and its web UI, packers, and profiles it runs with.
  installPhase = ''
    runHook preInstall
    ./gguf_geometry_test
    install -Dm755 strata $out/bin/strata
    mkdir -p $out/share/strata $out/libexec/strata
    install -m755 gemm_f32_parity mmvq_il_parity dequant_wide_parity $out/libexec/strata/
    install -m755 iq4xs_gu1_parity iq_avx2_parity dequant_fused_parity $out/libexec/strata/
    install -m755 conversation_snapshot_test $out/libexec/strata/
    cp -r ../{serve,tools,data} $out/share/strata/
    makeWrapper ${python.interpreter} $out/bin/strata-server \
      --chdir $out/share/strata --add-flags "-m serve.server"
    makeWrapper ${python.interpreter} $out/bin/strata-python \
      --set STRATA_GGUF_PY ${ggml}/gguf-py
    runHook postInstall
  '';

  # API key, Host/Origin and reasoning-effort routing checks.
  doInstallCheck = true;
  installCheckPhase = ''
    cd $out/share/strata && PYTHONDONTWRITEBYTECODE=1 ${python.interpreter} -m unittest serve.test_security serve.test_effort_paths
  '';
}
