{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  gitMinimal,
  libdrm,
  rocmPackages,
  cudaPackages,
  cudaArches ? cudaPackages.flags.realArches or [ ],
  autoAddDriverRunpath,
  vulkan-loader,
  vulkan-headers,
  openssl,
  buildEnv,

  config,
  # one of `[ null false "rocm" "cuda" "vulkan" ]`
  acceleration ? null,
}:

let
  validateFallback = lib.warnIf (config.rocmSupport && config.cudaSupport) (lib.concatStrings [
    "both `nixpkgs.config.rocmSupport` and `nixpkgs.config.cudaSupport` are enabled, "
    "but they are mutually exclusive; falling back to cpu"
  ]) (!(config.rocmSupport && config.cudaSupport));

  shouldEnable =
    mode: fallback: (acceleration == mode) || (fallback && acceleration == null && validateFallback);

  rocmRequested = shouldEnable "rocm" config.rocmSupport;
  cudaRequested = shouldEnable "cuda" config.cudaSupport;
  vulkanRequested = acceleration == "vulkan";

  enableRocm = rocmRequested && stdenv.hostPlatform.isLinux;
  enableCuda = cudaRequested && stdenv.hostPlatform.isLinux;
  enableVulkan = vulkanRequested && stdenv.hostPlatform.isLinux;

  rocmLibs = [
    rocmPackages.clr
    rocmPackages.hipblas-common
    rocmPackages.hipblas
    rocmPackages.rocblas
    rocmPackages.rocsolver
    rocmPackages.rocsparse
    rocmPackages.rocm-device-libs
    rocmPackages.rocm-smi
  ];

  cudaLibs = [
    cudaPackages.cuda_cudart
    cudaPackages.libcublas
    cudaPackages.cuda_cccl
  ];

  vulkanLibs = [
    vulkan-headers
    vulkan-loader
  ];

  # Extract the major version of CUDA. e.g. 11 12
  cudaMajorVersion = lib.versions.major cudaPackages.cuda_cudart.version;

  cudaToolkit = buildEnv {
    name = "cuda-merged-${cudaMajorVersion}";
    paths = map lib.getLib cudaLibs ++ [
      (lib.getOutput "static" cudaPackages.cuda_cudart)
      (lib.getBin (cudaPackages.cuda_nvcc.__spliced.buildHost or cudaPackages.cuda_nvcc))
    ];
  };

  cudaPath = lib.removeSuffix "-${cudaMajorVersion}" cudaToolkit;

  wrapperOptions = [
    "--suffix LD_LIBRARY_PATH : '${autoAddDriverRunpath.driverLink}/lib'"
  ]
  ++ lib.optionals enableRocm [
    "--suffix LD_LIBRARY_PATH : '${lib.makeLibraryPath rocmLibs}/lib'"
    "--set-default HIP_PATH '${lib.makeLibraryPath rocmLibs}'"
  ]
  ++ lib.optionals enableCuda [
    "--suffix LD_LIBRARY_PATH : '${lib.makeLibraryPath cudaLibs}'"
  ]
  ++ lib.optionals enableVulkan [
    "--suffix LD_LIBRARY_PATH : '${lib.makeLibraryPath vulkanLibs}'"
  ];
  wrapperArgs = builtins.concatStringsSep " " wrapperOptions;

in
stdenv.mkDerivation {
  pname = "llama-cpp";
  version = "b8748";

  src = fetchFromGitHub {
    owner = "ggerganov";
    repo = "llama.cpp";
    rev = "b8748"; 
    hash = "sha256-57RU5aNACYrk4EXS+6Y3bd2zT0jv9Rs1auRSmcMPoL8=";
  };

  nativeBuildInputs = [
    cmake
    gitMinimal
  ]
  ++ lib.optionals enableRocm [
    rocmPackages.llvm.bintools
    rocmLibs
  ]
  ++ lib.optionals enableCuda [ cudaPackages.cuda_nvcc ];

  buildInputs =
    [ openssl ]
    ++ lib.optionals enableRocm (rocmLibs ++ [ libdrm ])
    ++ lib.optionals enableCuda cudaLibs
    ++ lib.optionals enableVulkan vulkanLibs;

  cmakeFlags = [
    "-DBUILD_SHARED_LIBS=OFF"
    "-DLLAMA_BUILD_SERVER=ON"
    "-DLLAMA_OPENSSL=ON"
  ]
  ++ lib.optionals enableCuda [ "-DGGML_CUDA=ON" ]
  ++ lib.optionals enableRocm [ "-DGGML_HIPBLAS=ON" ]
  ++ lib.optionals enableVulkan [ "-DGGML_VULKAN=ON" ];

  # If CUDA is enabled, we need to set the architecture
  preConfigure = lib.optionalString enableCuda ''
    export CUDA_ARCHS="${builtins.concatStringsSep ";" (map (s: if builtins.match "sm_(.*)" s != null then (builtins.head (builtins.match "sm_(.*)" s)) else s) cudaArches)}"
  '';

  postFixup =
    lib.optionalString (enableRocm || enableCuda || enableVulkan) ''
      wrapProgram $out/bin/llama-server ${wrapperArgs}
    '';

  meta = {
    description = "Llama.cpp - Port of llama.cpp in C/C++";
    homepage = "https://github.com/ggerganov/llama.cpp";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
}