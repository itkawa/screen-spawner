#!/usr/bin/env bash
# Builds patched Hermes for Fedora or Arch Linux inside the build container.
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
system=${1:?system required}
if [ -f /tmp/ss-repackage ]; then
    rm -f /tmp/ss-repackage
    cd /build/Hermes
    exec bash /project/packaging/package-other.sh "$system"
fi
if [ ! -f /usr/local/share/ss-build-deps-ready ]; then
    bash /project/packaging/install-build-deps-other.sh
    mkdir -p /usr/local/share && touch /usr/local/share/ss-build-deps-ready
fi
cd /build
if [ ! -d Hermes/.git ]; then
    git clone --no-checkout https://github.com/MrOz59/Hermes Hermes
fi
cd Hermes
revision=7de12dc2d1c009c5cc4c0e67b8c537ea9e370e99
patches=(/project/patches/evdi-fix.patch /project/patches/openssl4.patch)
applied=true
for p in "${patches[@]}"; do git apply --reverse --check "$p" 2>/dev/null || applied=false; done
if [ "$applied" = false ]; then
    git checkout --detach --force "$revision"
    git reset --hard "$revision"
    for p in "${patches[@]}"; do git apply "$p"; done
fi
for attempt in 1 2 3; do
    if git submodule update --init --recursive; then break; fi
    [ "$attempt" -lt 3 ] || exit 1
    sleep 20
done
# A retained build tree has the shaders link from the previous build, and
# CMake 4.3+ cannot replace a link to a directory: the configure step makes
# it again.
[ ! -L build/assets/shaders ] || rm build/assets/shaders
configure() {
    cmake -S . -B build -G Ninja \
        -DSUNSHINE_ENABLE_CUDA=OFF -DCUDA_FAIL_ON_MISSING=OFF \
        -DCMAKE_INSTALL_PREFIX=/usr -DSUNSHINE_ASSETS_DIR=share/hermes \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
}
if ! configure; then
    # CMake 4 rejects Boost.Locale's header list, which names locale.hpp twice.
    locale_cmake=build/_deps/boost-src/libs/locale/CMakeLists.txt
    if [ -f "$locale_cmake" ] && ! grep -q 'REMOVE_ITEM sources_inc' "$locale_cmake"; then
        sed -i '/^list(FILTER sources_inc EXCLUDE REGEX "\^src\/")$/a list(REMOVE_ITEM sources_inc "${CMAKE_CURRENT_SOURCE_DIR}/include/boost/locale.hpp")' "$locale_cmake"
        grep -q 'REMOVE_ITEM sources_inc' "$locale_cmake"
    fi
    configure
fi
for attempt in 1 2 3; do
    if npm install; then break; fi
    [ "$attempt" -lt 3 ] || exit 1
    rm -rf node_modules package-lock.json
    sleep 60
done
if ! ninja -C build -j3; then
    echo '=== Retrying the interrupted build with one job ==='
    ninja -C build -j1
fi
bash /project/packaging/package-other.sh "$system"
