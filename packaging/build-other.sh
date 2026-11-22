#!/usr/bin/env bash
# Builds the Hermes package for Fedora 45 or Arch Linux in Docker.
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
system=${1:?Usage: packaging/build-other.sh fedora45|arch [--package-only]}
mode=${2:-build}
case "$system" in fedora45|arch) ;; *) exit 2 ;; esac
case "$mode" in build|--package-only) ;; *) exit 2 ;; esac
project=$(cd "$(dirname "$0")/.." && pwd)
. "$project/packaging/workspace.sh"
output=${PACKAGE_OUTPUT_DIR:-$workspace/packages-0.2.2}
logs=${PACKAGE_LOG_DIR:-$workspace/docker-tests}
mkdir -p "$output" "$logs"
exec 9>"$logs/.package-build.lock"
flock -n 9 || { echo 'ERROR: another package build is running.' >&2; exit 1; }
available=$(awk '/MemAvailable:/ {print int($2/1024/1024)}' /proc/meminfo)
required=${SS_BUILD_MIN_GIB:-7}
[ "$mode" != --package-only ] || required=1
[ "$available" -ge "$required" ] || { echo "ERROR: less than $required GiB available." >&2; exit 1; }
{
    docker build -f "$project/packaging/Dockerfile.$system" -t "screen-spawner-builder:$system" "$project"
    container="ss-package-$system-0.2.2"
    if docker container inspect "$container" >/dev/null 2>&1; then
        if [ "$mode" = --package-only ]; then
            marker=$(mktemp); printf 'Repackage\n' > "$marker"
            docker cp "$marker" "$container:/tmp/ss-repackage"; rm -f "$marker"
        fi
        docker start -a "$container"
        test "$(docker inspect -f '{{.State.ExitCode}}' "$container")" = 0
    else
        [ "$mode" != --package-only ] || { echo 'ERROR: no retained build container.' >&2; exit 1; }
        docker run --name "$container" --memory=6g --cpus=4 \
            -v "ss-package-$system:/build" -v "$project:/project:ro" -v "$output:/out" \
            "screen-spawner-builder:$system"
    fi
} 2>&1 | tee -a "$logs/package-build-$system.log"
exit "${PIPESTATUS[0]}"
