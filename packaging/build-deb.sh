#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
system=${1:?Usage: packaging/build-deb.sh ubuntu22.04|ubuntu24.04|ubuntu26.04|debian13}
mode=${2:-build}
case "$mode" in build|--package-only) ;; *) echo 'ERROR: unknown build mode.' >&2; exit 2 ;; esac
case "$system" in ubuntu22.04|ubuntu24.04|ubuntu26.04|debian13) ;; *) exit 2 ;; esac
project=$(cd "$(dirname "$0")/.." && pwd)
. "$project/packaging/workspace.sh"
output=${PACKAGE_OUTPUT_DIR:-$workspace/packages-0.2.0}
logs=${PACKAGE_LOG_DIR:-$workspace/docker-tests}
mkdir -p "$output" "$logs"
# One build across all distributions and shells. The user authorised using
# MemAvailable (reclaimable cache included) on 2026-11-12.
exec 9>"$logs/.package-build.lock"
flock -n 9 || { echo 'ERROR: another package build is running.' >&2; exit 1; }
free -g
available=$(awk '/MemAvailable:/ {print int($2/1024/1024)}' /proc/meminfo)
# SS_BUILD_MIN_GIB lowers this only when the owner allows it, e.g. for an
# incremental rebuild in a retained volume that recompiles a few files.
required=${SS_BUILD_MIN_GIB:-7}
# Repackaging only copies existing binaries/assets and runs CPack; no compilation.
[ "$mode" != --package-only ] || required=1
[ "$available" -ge "$required" ] || { echo "ERROR: less than $required GiB available; ask the owner before building." >&2; exit 1; }
{
    docker build -f "$project/packaging/Dockerfile.$system" -t "screen-spawner-builder:$system" "$project"
    # One container per package version; the build volume is shared, so a new
    # version rebuilds incrementally from the previous objects.
    container="ss-package-$system-0.2.0"
    if docker container inspect "$container" >/dev/null 2>&1; then
        if [ "$mode" = --package-only ]; then
            marker=$(mktemp)
            trap 'rm -f "$marker"' EXIT
            printf 'Repackage existing binaries\n' > "$marker"
            docker cp "$marker" "$container:/tmp/ss-repackage"
        fi
        docker start -a "$container"
        test "$(docker inspect -f '{{.State.ExitCode}}' "$container")" = 0
    else
        [ "$mode" != --package-only ] || { echo 'ERROR: no retained build container.' >&2; exit 1; }
        docker run --name "$container" --memory=6g --cpus=4 \
            -v "ss-package-$system:/build" -v "$project:/project:ro" -v "$output:/out" \
            "screen-spawner-builder:$system"
    fi
    # Older retained containers can still have the previous output bind mount.
    artifact="hermes-screen-spawner_0.5.1+ss0.2.0_${system}_amd64.deb"
    copied=$(mktemp "$output/.package-XXXXXX")
    docker cp "$container:/out/$artifact" "$copied"
    mv -f "$copied" "$output/$artifact"
} 2>&1 | tee -a "$logs/package-build-$system.log"
