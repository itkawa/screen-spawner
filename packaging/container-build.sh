#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
system=${1:?system required}
export DEBIAN_FRONTEND=noninteractive
[ "$(dpkg --print-architecture)" = amd64 ] || { echo "ERROR: use an amd64 build container." >&2; exit 1; }
if [ -f /tmp/ss-repackage ]; then
    rm -f /tmp/ss-repackage
    cd /build/Hermes
    exec bash /project/packaging/package-deb.sh "$system"
fi
if [ ! -f /usr/local/share/ss-build-deps-ready ]; then
    bash /project/packaging/install-build-deps.sh
    touch /usr/local/share/ss-build-deps-ready
fi
cd /build
if [ ! -d Hermes/.git ]; then
    git clone --no-checkout https://github.com/MrOz59/Hermes Hermes
fi
cd Hermes
git checkout --detach 7de12dc2d1c009c5cc4c0e67b8c537ea9e370e99
if ! git apply --reverse --check /project/patches/evdi-fix.patch 2>/dev/null; then
    git apply /project/patches/evdi-fix.patch
fi
for attempt in 1 2 3; do
    if git submodule update --init --recursive; then break; fi
    [ "$attempt" -lt 3 ] || exit 1
    sleep 20
done
extra=()
if [ "$system" = ubuntu22.04 ]; then
    extra+=(-DCMAKE_C_COMPILER=/usr/bin/gcc-13 -DCMAKE_CXX_COMPILER=/usr/bin/g++-13
        '-DCMAKE_EXE_LINKER_FLAGS=-static-libstdc++ -static-libgcc')
fi
cmake -S . -B build -G Ninja \
    -DSUNSHINE_ENABLE_CUDA=OFF -DCUDA_FAIL_ON_MISSING=OFF \
    -DCMAKE_INSTALL_PREFIX=/usr -DSUNSHINE_ASSETS_DIR=share/hermes "${extra[@]}"
# Retry the web dependency download separately; do not hide C++ build failures.
web_dir=.
for attempt in 1 2 3; do
    if (cd "$web_dir" && npm install); then break; fi
    [ "$attempt" -lt 3 ] || exit 1
    rm -rf "$web_dir/node_modules" "$web_dir/package-lock.json"
    sleep 60
done
if ! ninja -C build -j3; then
    echo '=== Retrying the interrupted build with one job ==='
    ninja -C build -j1
fi
bash /project/packaging/package-deb.sh "$system"
