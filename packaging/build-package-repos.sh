#!/usr/bin/env bash
# Build everything the package repositories need for one Screen Spawner
# version, without publishing anything:
#   OUT/packages/  screen-spawner .deb and .rpm, SHA256SUMS
#   OUT/site/      the itkawa/screen-spawner-packages working tree: apt/ and
#                  rpm/ repositories, signed, the key and install-repo.sh
# The AUR packages need the published tag's tarball: aur-prepare.sh, after it.
# Usage: build-package-repos.sh VERSION OUT
# Hermes packages: HERMES_DEBS (default builds v0.2.0) and HERMES_RPMS (v0.2.1).
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
version=${1:?version} out=${2:?output dir}
here="$(cd "$(dirname "$0")" && pwd)"
builds="/home/shared/screen spawner hermes"
hermes_debs=${HERMES_DEBS:-$builds/packages-0.2.0}
hermes_rpms=${HERMES_RPMS:-$builds/packages-0.2.1}
keydir=${KEY_DIR:-/home/user/work/PROJECTS/ScreenTablet/signing-key}
export GNUPGHOME="$keydir/gnupg"
export SIGNING_KEY=${SIGNING_KEY:-280E1BCC04143CB407AB28C1E906907232FE0F54}
export SECRET_KEY="$keydir/SECRET-screen-spawner-packages.asc"

mkdir -p "$out/packages"
out="$(cd "$out" && pwd)"
rm -f "$out/packages"/screen-spawner*
deb=$("$here/package-app-deb.sh" "$version" "$out/packages")
rpm=$("$here/package-app-rpm.sh" "$version" "$out/packages" | tail -n 1)
(cd "$out/packages" && sha256sum "$(basename "$deb")" "$(basename "$rpm")" > SHA256SUMS)

# Keep the working tree's own files (.git, README.md); rebuild the rest.
mkdir -p "$out/site"
"$here/build-apt-repo.sh" "$out/site" "$deb" "$hermes_debs"
"$here/build-dnf-repo.sh" "$out/site" "$rpm" "$hermes_rpms"
install -m 644 "$here/packages-site-README.md" "$out/site/README.md"
echo
echo "Packages: $out/packages"
cat "$out/packages/SHA256SUMS"
echo "Site:     $out/site"
