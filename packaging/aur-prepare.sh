#!/usr/bin/env bash
# Fill in the AUR packages for a Screen Spawner version: version number and
# the checksum of its source tarball, plus .SRCINFO (made in an Arch container).
# Usage: aur-prepare.sh VERSION OUTPUT_DIR [TARBALL] [PKGREL]
#   TARBALL  the source tarball; by default GitHub's tarball of tag vVERSION,
#            downloaded (the tag has to be published first).
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
version=${1:?version} out=${2:?output dir}
tarball=${3:-} pkgrel=${4:-1}
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
cp -r "$here/aur/." "$out/"
if [ -z "$tarball" ]; then
    tarball="$out/screen-spawner/screen-spawner-$version.tar.gz"
    curl -fsSL -o "$tarball" "https://github.com/itkawa/screen-spawner/archive/refs/tags/v$version.tar.gz"
fi
sum=$(sha256sum "$tarball" | cut -d' ' -f1)
sed -i -e "s/@VERSION@/$version/" -e "s/@SHA256@/$sum/" -e "s/^pkgrel=1$/pkgrel=$pkgrel/" \
    "$out/screen-spawner/PKGBUILD"
docker run --rm -v "$out:/aur" archlinux:latest bash -euo pipefail -c '
pacman -Sy --noconfirm --needed -q base-devel >/dev/null 2>&1
useradd -m builder
chown -R builder /aur
for d in /aur/*/; do (cd "$d" && runuser -u builder -- makepkg --printsrcinfo > .SRCINFO); done
chown -R '"$(id -u):$(id -g)"' /aur
'
echo "AUR packages ready in $out"
