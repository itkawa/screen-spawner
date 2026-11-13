#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
system=${1:?Usage: packaging/test-deb.sh SYSTEM [package|installer|source]}
mode=${2:-package}
case "$system" in
    ubuntu22.04) base=ubuntu:22.04; clean=screen-spawner-cleantest ;;
    ubuntu24.04) base=ubuntu:24.04; clean=screen-spawner-cleantest-2404 ;;
    ubuntu26.04) base=ubuntu:26.04; clean=screen-spawner-cleantest-2604 ;;
    debian13) base=debian:13; clean=screen-spawner-cleantest-deb13 ;;
    mint22) base=screen-spawner-cleantest-mint22; clean=$base ;;
    *) exit 2 ;;
esac
case "$mode" in package) image=$base ;; installer|source) image=$clean ;; *) exit 2 ;; esac
project=$(cd "$(dirname "$0")/.." && pwd)
. "$project/packaging/workspace.sh"
mkdir -p "$workspace/docker-tests"
exec 9>"$workspace/docker-tests/.package-build.lock"
flock -n 9 || { echo 'ERROR: another build or test is running.' >&2; exit 1; }
free -g
available=$(awk '/MemAvailable:/ {print int($2/1024/1024)}' /proc/meminfo)
[ "$available" -ge 7 ] || { echo 'ERROR: less than 7 GiB available; ask the owner.' >&2; exit 1; }
docker run --name "ss-test-011r3-$system-$mode" --memory=6g --cpus=4 --user root \
    -e TEST_SYSTEM="$system" -e TEST_MODE="$mode" \
    -v "$project:/project:ro" -v "$workspace/packages-0.1.1:/packages:ro" \
    "$image" bash /project/packaging/container-test.sh \
    2>&1 | tee "$workspace/docker-tests/package-test-$system-$mode.log"
