#!/usr/bin/env bash
# Build the signed DNF repository that GitHub Pages serves next to the APT
# one: rpm/fedora/<release>/x86_64 with that release's Hermes package and
# the screen-spawner package, every rpm and the metadata signed.
# Runs createrepo_c and rpmsign in a fedora container.
# Usage: build-dnf-repo.sh SITE_DIR APP_RPM HERMES_RPM_DIR
#   SITE_DIR        the repository's working copy (its rpm/ is rebuilt)
#   APP_RPM         screen-spawner-<version>-<release>.noarch.rpm
#   HERMES_RPM_DIR  folder with hermes-screen-spawner-*.fc<N>.x86_64.rpm and SHA256SUMS
# SECRET_KEY (armored secret key file) and SIGNING_KEY (fingerprint) sign.
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
site=${1:?site dir required}
app_rpm=${2:?app rpm required}
hermes_dir=${3:?hermes rpm dir required}
secret=${SECRET_KEY:?SECRET_KEY required}
key=${SIGNING_KEY:?SIGNING_KEY required}
image=${FEDORA_IMAGE:-fedora:45}

(cd "$hermes_dir" && sha256sum --check --ignore-missing --quiet SHA256SUMS)
mkdir -p "$site"
site="$(cd "$site" && pwd)"
rm -rf "$site/rpm"
releases=()
for hermes in "$hermes_dir"/hermes-screen-spawner-*.fc*.x86_64.rpm; do
    [ -f "$hermes" ] || continue
    release=$(basename "$hermes" | sed -n 's/.*\.fc\([0-9]\+\)\.x86_64\.rpm$/\1/p')
    dir="$site/rpm/fedora/$release/x86_64"
    mkdir -p "$dir"
    cp "$hermes" "$app_rpm" "$dir/"
    releases+=("$release")
done
[ ${#releases[@]} -gt 0 ] || { echo "No Hermes rpm in $hermes_dir" >&2; exit 1; }

docker run --rm --memory=4g --cpus=4 -v "$site/rpm:/rpm" -v "$(realpath "$secret"):/key.asc:ro" \
    -e KEY="$key" -e OWNER="$(id -u):$(id -g)" "$image" bash -euo pipefail -c '
dnf install -y -q createrepo_c rpm-sign gnupg2 >/dev/null
export GNUPGHOME=$(mktemp -d)
gpg --batch --quiet --import /key.asc
for dir in /rpm/fedora/*/x86_64; do
    rpmsign --addsign --define "_openpgp_sign_id $KEY" --define "_gpg_name $KEY" "$dir"/*.rpm >/dev/null
    rpmkeys --checksig "$dir"/*.rpm >/dev/null 2>&1 || true
    createrepo_c --quiet "$dir"
    gpg --batch --yes --local-user "$KEY" --armor --detach-sign -o "$dir/repodata/repomd.xml.asc" "$dir/repodata/repomd.xml"
done
chown -R "$OWNER" /rpm
'
gpg --armor --export "$key" > "$site/screen-spawner-packages.asc" 2>/dev/null || true
echo "DNF repository built in $site/rpm for Fedora ${releases[*]}"
