{ pkgs }:

(pkgs.qemu_kvm.override {
  alsaSupport = false;
  pulseSupport = false;
  sdlSupport = false;
  jackSupport = false;
  gtkSupport = false;
  vncSupport = false;
  smartcardSupport = false;
  spiceSupport = false;
  ncursesSupport = false;
  libiscsiSupport = false;
  tpmSupport = true;
  numaSupport = false;
  seccompSupport = false;
  guestAgentSupport = false;
}).overrideAttrs (super:  {
  src = pkgs.fetchurl {
    url = "https://download.qemu.org/qemu-10.1.3.tar.xz";
    hash = "sha256-nXXzMcGly5tuuP2fZPVj7C6rNGyCLLl/izXNgtPxFHk=";
  };
  patches = [
    "${pkgs.fetchFromGitHub {
      owner = "proxmox";
      repo = "pve-qemu";
      rev = "14afbdd55f04d250bd679ca1ad55d3f47cd9d4c8";
      hash = "sha256-lSJQA5SHIHfxJvMLIID2drv2H43crTPMNIlIT37w9Nc=";
    }}/debian/patches/pve/0027-PVE-Backup-add-vma-backup-format-code.patch"
  ];
  postPatch = ''
    substituteInPlace vma-reader.c \
      --replace "sysemu/block-backend.h" "system/block-backend.h"
    substituteInPlace vma.c \
      --replace "sysemu/block-backend.h" "system/block-backend.h" \
      --replace "qapi/qmp/qdict.h" "qobject/qdict.h" \
      --replace "qapi/qmp/qstring.h" "qobject/qstring.h" \
      --replace "qapi/qmp/qerror.h" "qapi/qmp/qerror.h"
    substituteInPlace meson.build \
      --replace "dependencies: [authz, block, crypto, io, qom]" "dependencies: [authz, block, crypto, io, qom, qemuutil, libuuid]"
  '';
  buildInputs = super.buildInputs ++ [ pkgs.libuuid ];
  nativeBuildInputs = super.nativeBuildInputs ++ [ pkgs.perl ];
})

