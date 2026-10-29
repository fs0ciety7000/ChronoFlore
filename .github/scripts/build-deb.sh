#!/usr/bin/env bash
# Packages the Linux export (PCK embedded) as a .deb:
#   /opt/chronoflore/ChronoFlore.x86_64, /usr/bin/chronoflore (launcher),
#   a .desktop entry and a 256 px icon.
# Usage: build-deb.sh <ChronoFlore.x86_64> <icon-256.png> <version> <out.deb>
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "usage: $0 <ChronoFlore.x86_64> <icon-256.png> <version> <out.deb>" >&2
  exit 2
fi
binary=$1 icon=$2 version=$3 out=$4

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
chmod 755 "$root"

install -Dm755 "$binary" "$root/opt/chronoflore/ChronoFlore.x86_64"
install -Dm644 "$icon" "$root/usr/share/icons/hicolor/256x256/apps/chronoflore.png"

mkdir -p "$root/usr/bin"
cat > "$root/usr/bin/chronoflore" <<'SH'
#!/bin/sh
exec /opt/chronoflore/ChronoFlore.x86_64 "$@"
SH
chmod 755 "$root/usr/bin/chronoflore"

mkdir -p "$root/usr/share/applications"
cat > "$root/usr/share/applications/chronoflore.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=ChronoFlore
Comment=Huit heures de sommeil. Toute une flore à capturer.
Exec=chronoflore
Icon=chronoflore
Terminal=false
Categories=Game;ActionGame;
DESKTOP
chmod 644 "$root/usr/share/applications/chronoflore.desktop"

installed_kb=$(du -sk --exclude=DEBIAN "$root" | cut -f1)
mkdir -p "$root/DEBIAN"
cat > "$root/DEBIAN/control" <<CONTROL
Package: chronoflore
Version: $version
Section: games
Priority: optional
Architecture: amd64
Depends: libc6 (>= 2.31), libgl1, libx11-6, libxcursor1, libxinerama1, libxext6, libxrandr2, libxi6, libasound2 | libasound2t64, libpulse0, libfontconfig1, libudev1
Installed-Size: $installed_kb
Maintainer: ChronoFlore <noreply@chronoflore.cardormedia.com>
Homepage: https://chronoflore.cardormedia.com
Description: Rêve lucide en action-arcade isométrique
 Une botaniste-chasseuse capture les plantes nées de ses émotions avant de se
 réveiller. Une run dure une nuit de huit heures.
CONTROL

# Files owned by root whatever the builder's uid; xz is the dpkg default.
dpkg-deb --root-owner-group --build "$root" "$out"
