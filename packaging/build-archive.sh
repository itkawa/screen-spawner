#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
system=${1:?Usage: build-archive.sh SYSTEM [SOURCE_ARCHIVE_ROOT]}
case "$system" in ubuntu22.04|ubuntu24.04|ubuntu26.04|debian13) ;; *) exit 2 ;; esac
source_root=${2:-$(cd "$(dirname "$0")/../.." && pwd)}
source_root=$(cd "$source_root" && pwd)
test -f "$source_root/SOURCE-MANIFEST.json"
output=${ARCHIVE_OUTPUT_DIR:-$(dirname "$source_root")/rebuilt-packages}
mkdir -p "$output"
exec 9>"$output/.build.lock"
flock -n 9 || { echo 'ERROR: another archive build is running.' >&2; exit 1; }
free -g
available=$(awk '/MemAvailable:/ {print int($2/1024/1024)}' /proc/meminfo)
[ "$available" -ge 7 ] || { echo 'ERROR: less than 7 GiB available; ask the owner.' >&2; exit 1; }
image=${SOURCE_BUILD_IMAGE:-screen-spawner-archive-builder:$system}
if [ -z "${SOURCE_BUILD_IMAGE:-}" ]; then
    docker build -f "$source_root/build-support/packaging/Dockerfile.$system" \
        -t "$image" "$source_root/build-support"
fi
docker run --rm --memory=6g --cpus=4 --network="${SOURCE_BUILD_NETWORK:-bridge}" \
    -e SOURCE_BUILD_JOBS="${SOURCE_BUILD_JOBS:-1}" \
    -v "ss-archive-$system:/build" -v "$source_root:/source:ro" \
    -v "$source_root/build-support:/project:ro" -v "$output:/out" \
    --entrypoint bash "$image" /project/packaging/container-archive-build.sh "$system"
