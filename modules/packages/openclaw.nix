{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
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

  npmDepsHash = "sha256-1r2mj1qy2j5lagcg5x7rc733pilf8wppzq7wmwngfd352q0zp48l";

  installPhase = ''
    mkdir -p $out/bin
    cp -r . $out
    ln -s $out/bin/openclaw $out/bin/openclaw 
  '';
}
/t
