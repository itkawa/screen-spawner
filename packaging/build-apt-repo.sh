#!/usr/bin/env bash
# Build the signed APT repository that GitHub Pages serves from
# itkawa/screen-spawner-packages: one suite per supported release, each with
# its own Hermes package and the same screen-spawner package.
# Usage: build-apt-repo.sh SITE_DIR APP_DEB HERMES_DEB_DIR
#   SITE_DIR        the repository's working copy (its apt/ is rebuilt)
#   APP_DEB         screen-spawner_<version>-<release>_all.deb
#   HERMES_DEB_DIR  folder with the four hermes-screen-spawner debs and SHA256SUMS
# GNUPGHOME and SIGNING_KEY (fingerprint) select the signing key.
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
site=${1:?site dir required}
app_deb=${2:?app deb required}
hermes_dir=${3:?hermes deb dir required}
key=${SIGNING_KEY:?SIGNING_KEY required}
here="$(cd "$(dirname "$0")" && pwd)"

# suite  package system tag
suites="jammy:ubuntu22.04 noble:ubuntu24.04 resolute:ubuntu26.04 trixie:debian13"

(cd "$hermes_dir" && sha256sum --check --ignore-missing --quiet SHA256SUMS)

repo="$site/apt"
rm -rf "$repo"
mkdir -p "$repo/pool/main/h/hermes-screen-spawner" "$repo/pool/main/s/screen-spawner"
cp "$app_deb" "$repo/pool/main/s/screen-spawner/"
for entry in $suites; do
    tag=${entry#*:}
    found=("$hermes_dir"/hermes-screen-spawner_*_"${tag}"_amd64.deb)
    [ ${#found[@]} -eq 1 ] && [ -f "${found[0]}" ] || { echo "No Hermes package for $tag" >&2; exit 1; }
    cp "${found[0]}" "$repo/pool/main/h/hermes-screen-spawner/"
done

cd "$repo"
all="$(mktemp)"
trap 'rm -f "$all"' EXIT
apt-ftparchive packages pool > "$all"
for entry in $suites; do
    suite=${entry%%:*} tag=${entry#*:}
    dir="dists/$suite/main/binary-amd64"
    mkdir -p "$dir"
    # This suite's Hermes package, and every package that is not Hermes.
    python3 - "$all" "$tag" > "$dir/Packages" <<'PY'
import sys
text, tag = open(sys.argv[1]).read(), sys.argv[2]
for stanza in text.strip().split("\n\n"):
    fields = dict(line.split(": ", 1) for line in stanza.splitlines() if ": " in line and not line.startswith(" "))
    if fields["Package"] != "hermes-screen-spawner" or f"_{tag}_" in fields["Filename"]:
        print(stanza + "\n")
PY
    gzip -9n -k "$dir/Packages"
    apt-ftparchive \
        -o APT::FTPArchive::Release::Origin="Screen Spawner" \
        -o APT::FTPArchive::Release::Label="Screen Spawner" \
        -o APT::FTPArchive::Release::Suite="$suite" \
        -o APT::FTPArchive::Release::Codename="$suite" \
        -o APT::FTPArchive::Release::Architectures="amd64" \
        -o APT::FTPArchive::Release::Components="main" \
        -o APT::FTPArchive::Release::Description="Screen Spawner and its Hermes for $suite" \
        release "dists/$suite" > "dists/$suite/Release.tmp"
    mv "dists/$suite/Release.tmp" "dists/$suite/Release"
    gpg --batch --yes --local-user "$key" --clearsign -o "dists/$suite/InRelease" "dists/$suite/Release"
    gpg --batch --yes --local-user "$key" --armor --detach-sign -o "dists/$suite/Release.gpg" "dists/$suite/Release"
done

# The key, armored for reading and binary for apt's Signed-By.
gpg --armor --export "$key" > "$site/screen-spawner-packages.asc"
gpg --export "$key" > "$site/screen-spawner-packages.gpg"
install -m 644 "$here/install-repo.sh" "$site/install-repo.sh"
touch "$site/.nojekyll"
echo "APT repository built in $repo"
