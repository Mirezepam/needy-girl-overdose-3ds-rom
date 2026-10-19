#!/usr/bin/env bash
# Configure the devkitPro pacman repositories inside MSYS2 and install the 3DS toolchain.
# Run from an MSYS2 shell:  /c/msys64/usr/bin/bash -lc "/path/to/setup_devkitpro_msys2.sh"
set -euo pipefail

KEY=BC26F752D25B92CE272E0F44F7FD5492264BB9D0
pacman-key --recv-keys "$KEY" --keyserver keyserver.ubuntu.com
pacman-key --lsign-key "$KEY"
pacman -U --noconfirm https://pkg.devkitpro.org/devkitpro-keyring.pkg.tar.zst

if ! grep -q "^\[dkp-libs\]" /etc/pacman.conf; then
  cat >> /etc/pacman.conf <<'EOF'

[dkp-libs]
Server = https://pkg.devkitpro.org/packages

[dkp-windows]
Server = https://pkg.devkitpro.org/packages/windows/$arch/
EOF
fi

pacman -Sy --noconfirm
pacman -S --noconfirm --needed 3ds-dev make
# optional portlibs used by the port (audio decoding)
pacman -S --noconfirm --needed 3ds-libvorbisidec 3ds-libogg || true
echo "devkitPro installed at /opt/devkitpro"
