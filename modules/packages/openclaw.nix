{ 
  lib,
  fetchFromGitHub,
  stdenv,
  ...
}:

# Minimal package - avoids OOM issues with building from source
# Uses source as-is without compilation
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
    mkdir -p $out/bin
    # Copy entire source directory as-is
    cp -r . $out/lib/openclaw/

    # Create a portable build script
    cat <<EOF > $out/bin/openclaw-build
#!/usr/bin/env bash
set -e
BUILD_DIR=\$1
if [ -z "\$BUILD_DIR" ]; then
  echo "Usage: openclaw-build <build_directory>"
  exit 1
fi

cd "\$BUILD_DIR"

echo "Building OpenClaw from source..."
# Clean previous failed attempts
rm -rf node_modules dist

# Aggressively limit memory and concurrency
export NODE_OPTIONS="--max-old-space-size=2048"
pnpm config set concurrency 1

pnpm install --child-concurrency 1 --prefer-offline --no-audit
pnpm run build
echo "OpenClaw build completed."
EOF
    chmod +x $out/bin/openclaw-build
  '';

  meta = with lib; {
    description = "OpenClaw AI Assistant - 2026.4.15 (source)";
    homepage = "https://github.com/openclaw/openclaw";
    license = licenses.mit;
  };
}

