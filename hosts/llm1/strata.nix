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
  # The server and the one-time packers (iq_pack.py, mtp_*.py) need these.
  python = python3.withPackages (
    p: with p; [
      jinja2
      regex
      numpy
      psutil
      pillow
    ]
  );
in
cuda.backendStdenv.mkDerivation {
  pname = "strata";
  version = "0.1.39-unstable-2026-10-05";

  src = fetchFromGitHub {
    owner = "Niko1221";
    repo = "Strata";
    rev = "6f32ec070f23ced9f50e704d854d775da52591ab";
    hash = "sha256-9jqmV+AbGKiOqW1DvKjqBLVXmJCI9o6WI85QoHj5vBI=";
  };

  patches = [
    # The server takes one API key; accept a one-key-per-line file.
    ./strata-api-keys.patch
    # Engine changes for this card and for two concurrent agents (docs/llm1.md, "Engine patch").
    ./strata-performance.patch
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
    (lib.cmakeBool "STRATA_BUILD_TESTS" false)
    (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" "61")
    (lib.cmakeFeature "STRATA_GGML_DIR" "${ggml}")
  ];
  ninjaFlags = [ "strata" ];

  # Strata forces GGML_NATIVE, which the Nix compiler wrapper strips; target
  # hv1's E5-2690 v4 (`cpu: host`) explicitly instead, as hosts/llm1/llm.nix does.
  env.NIX_CFLAGS_COMPILE = "-march=broadwell -mtune=broadwell";

  # The engine, plus the Python server, packers, and profiles it runs with.
  installPhase = ''
    runHook preInstall
    install -Dm755 strata $out/bin/strata
    mkdir -p $out/share/strata
    cp -r ../{serve,tools,data} $out/share/strata/
    makeWrapper ${python.interpreter} $out/bin/strata-server \
      --chdir $out/share/strata --add-flags "-m serve.server"
    makeWrapper ${python.interpreter} $out/bin/strata-python \
      --set STRATA_GGUF_PY ${ggml}/gguf-py
    runHook postInstall
  '';

  # The API key and Host/Origin checks, including the key-file patch.
  doInstallCheck = true;
  installCheckPhase = ''
    cd $out/share/strata && PYTHONDONTWRITEBYTECODE=1 ${python.interpreter} -m unittest serve.test_security
  '';
}
