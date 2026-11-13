#!/usr/bin/env bash
# Run by the owner only, after reviewing local changes and test results.
set -euo pipefail
project=${SCREEN_SPAWNER_PROJECT_DIR:-/home/shared/ScreenTablet/screen-spawner}
cd "$project"
. "$project/packaging/workspace.sh"
# Trust only this explicitly selected checkout, without changing global Git config.
git() { command git -c safe.directory="$project" "$@"; }
[ "$(git symbolic-ref --short HEAD)" = main ] || { echo 'ERROR: check out main before publishing.' >&2; exit 1; }
# Publish the separately reviewed 0.1.0 README fold before creating 0.1.1.
if ! git merge-base --is-ancestor 9a1794363a34e1dcb72fb6545c84a6ae725355d3 HEAD; then
    echo 'ERROR: run ~/fold-readme-into-0.1.0.sh first, then publish 0.1.1.' >&2
    exit 1
fi
expected_email=10118073+itkawa@users.noreply.github.com
[ "$(git config --local user.email)" = "$expected_email" ] || {
    echo 'ERROR: repository author email does not match the project noreply address.' >&2
    exit 1
}
if grep -q 'PENDING_' install.sh; then
    echo 'ERROR: package checksums are incomplete.' >&2
    exit 1
fi
if git show-ref --verify --quiet refs/tags/v0.1.1; then
    echo 'ERROR: v0.1.1 already exists locally; inspect it before publishing.' >&2
    exit 1
fi
test -s "$workspace/packages-0.1.1/hermes-screen-spawner-0.1.1-source.tar.xz" || {
    echo 'ERROR: complete corresponding-source archive is missing.' >&2; exit 1;
}
grep -q 'hermes-screen-spawner-0.1.1-source.tar.xz' "$workspace/packages-0.1.1/SHA256SUMS" || {
    echo 'ERROR: source archive checksum is missing.' >&2; exit 1;
}
(cd "$workspace/packages-0.1.1" && sha256sum -c SHA256SUMS)
git add install.sh uninstall.sh README.md CHANGELOG.md packaging/
git -c user.name=itkawa -c user.email="$expected_email" commit -m "Install Hermes from prebuilt packages"
git push origin main
git tag v0.1.1
git push origin v0.1.1
# v0.1.0 and its history are left unchanged.
