{ 
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
  stdenv,
  ...
}:

let
  src = fetchFromGitHub {
    owner = "openclaw";
    repo = "openclaw";
    rev = "v2026.4.15";
    hash = "sha256-QsoiV52a0rcTL4fvF6c/aC1/Krq4qKptYOwlW4N6/4c=";
  };

  # Generate the package-lock.json file
  lockFile = stdenv.mkDerivation {
    name = "openclaw-package-lock.json";
    inherit src;
    nativeBuildInputs = [ nodejs ];
    phases = [ "unpackPhase" "buildPhase" "installPhase" ];
    buildPhase = ''
      npm install --package-lock-only --legacy-peer-deps
    '';
    installPhase = ''
      cp package-lock.json $out
    '';
  };
in
buildNpmPackage {
  pname = "openclaw";
  version = "2026.4.15";

  inherit src;

  postUnpack = ''
    cp ${lockFile} source/package-lock.json
  '';

  npmDepsHash = "sha256-EVFah6DVKgdokKgv9UMQ1iBFwMuDUTONSsdZ7kqjyDw=";

  installPhase = ''
    mkdir -p $out/bin
    cp -r . $out
    ln -s $out/bin/openclaw $out/bin/openclaw 
  '';
}
