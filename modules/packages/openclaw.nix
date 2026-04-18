{ 
  lib,
  fetchFromGitHub,
  stdenv,
  nodejs,
  pnpm,
  ...
}:

stdenv.mkDerivation {
  pname = "openclaw";
  version = "2026.4.15";

  src = fetchFromGitHub {
    owner = "openclaw";
    repo = "openclaw";
    rev = "v2026.4.15";
    hash = "sha256-QsoiV52a0rcTL4fvF6c/aC1/Krq4qKptYOwlW4N6/4c=";
  };

  nativeBuildInputs = [ nodejs pnpm ];

  buildPhase = ''
    # Set pnpm home to a writable location in the build directory
    export PNPM_HOME="$PWD/.pnpm"
    mkdir -p "$PNPM_HOME"
    export PATH="$PNPM_HOME:$PATH"
    
    # Install dependencies with pnpm
    pnpm install --frozen-lockfile
    
    # Build TypeScript
    pnpm run build
  '';

  installPhase = ''
    mkdir -p $out/lib/openclaw
    cp -r . $out/lib/openclaw/
  '';

  meta = with lib; {
    description = "OpenClaw AI Assistant";
    homepage = "https://github.com/openclaw/openclaw";
    license = licenses.mit;
  };
}
