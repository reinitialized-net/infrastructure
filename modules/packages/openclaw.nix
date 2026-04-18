{ 
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
  ...
}:

buildNpmPackage {
  pname = "openclaw";
  version = "2026.4.15";

  src = fetchFromGitHub {
    owner = "openclaw";
    repo = "openclaw";
    rev = "v2026.4.15";
    hash = "sha256-QsoiV52a0rcTL4fvF6c/aC1/Krq4qKptYOwlW4N6/4c=";
  };

  postPatch = ''
    npm install --package-lock-only --legacy-peer-deps
  '';

  npmDepsHash = "sha256-EVFah6DVKgdokKgv9UMQ1iBFwMuDUTONSsdZ7kqjyDw=";

  installPhase = ''
    mkdir -p $out/bin
    cp -r . $out
    ln -s $out/bin/openclaw $out/bin/openclaw 
  '';
}
