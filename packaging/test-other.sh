#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
system=${1:?Usage: packaging/test-other.sh fedora45|arch package|installer}
mode=${2:-package}
case "$system" in fedora45) image=fedora:45 ;; arch) image=archlinux:latest ;; *) exit 2 ;; esac
case "$mode" in package|installer) ;; *) exit 2 ;; esac
project=$(cd "$(dirname "$0")/.." && pwd)
. "$project/packaging/workspace.sh"
mkdir -p "$workspace/docker-tests"
exec 9>"$workspace/docker-tests/.package-build.lock"
flock -n 9 || { echo 'ERROR: another build or test is running.' >&2; exit 1; }
docker run --rm --name "ss-test-031-$system-$mode" --memory=6g --cpus=4 --user root \
    -e TEST_SYSTEM="$system" -e TEST_MODE="$mode" \
    -v "$project:/project:ro" -v "$workspace/packages-0.2.1:/packages:ro" \
    "$image" bash /project/packaging/container-test-other.sh \
    2>&1 | tee "$workspace/docker-tests/package-test-$system-$mode.log"
exit "${PIPESTATUS[0]}"
