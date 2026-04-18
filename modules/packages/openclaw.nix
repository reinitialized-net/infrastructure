{ 
  lib,
  fetchFromGitHub,
  stdenv,
  ...
}:

# OpenClaw package - provides source code only
# npm install is handled at runtime by the openclaw-gateway systemd service
# This avoids network access issues in the Nix sandbox
stdenv.mkDerivation {
  pname = "openclaw";
  version = "2026.4.15";

  src = fetchFromGitHub {
    owner = "openclaw";
    repo = "openclaw";
    rev = "v2026.4.15";
    hash = "sha256-QsoiV52a0rcTL4fvF6c/aC1/Krq4qKptYOwlW4N6/4c=";
  };

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/lib/openclaw
    cp -r . $out/lib/openclaw/
  '';

  meta = with lib; {
    description = "OpenClaw AI Assistant - source code package";
    homepage = "https://github.com/openclaw/openclaw";
    license = licenses.mit;
  };
}
