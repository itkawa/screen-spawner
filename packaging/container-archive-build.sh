#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
system=${1:?system required}
if [ ! -f /usr/local/share/ss-build-deps-ready ]; then
    bash /project/packaging/install-build-deps.sh
fi
if [ ! -d /build/Hermes ]; then
    cp -a /source/Hermes /build/Hermes
    cp -a /source/fetched-sources/npm-node_modules /build/Hermes/node_modules
fi
cd /build/Hermes
cp "/source/build-support/package-lock.$system.json" package-lock.json
export BRANCH=HEAD BUILD_VERSION=0.5.1.7de12dc2.dirty
export COMMIT=7de12dc2d1c009c5cc4c0e67b8c537ea9e370e99
export CLONE_URL=https://github.com/MrOz59/Hermes
extra=()
if [ "$system" = ubuntu22.04 ]; then
    extra+=(-DCMAKE_C_COMPILER=/usr/bin/gcc-13 -DCMAKE_CXX_COMPILER=/usr/bin/g++-13
        '-DCMAKE_EXE_LINKER_FLAGS=-static-libstdc++ -static-libgcc')
fi
cmake -S . -B build -G Ninja \
    -DSUNSHINE_ENABLE_CUDA=OFF -DCUDA_FAIL_ON_MISSING=OFF \
    -DCMAKE_INSTALL_PREFIX=/usr -DSUNSHINE_ASSETS_DIR=share/hermes \
    -DFETCHCONTENT_SOURCE_DIR_BOOST=/source/fetched-sources/boost-1.89.0 \
    -DFETCHCONTENT_SOURCE_DIR_JSON=/source/fetched-sources/nlohmann-json-3.11.3 \
    -DNPM_OFFLINE=ON "${extra[@]}"
mkdir -p build/_deps
[ -e build/_deps/boost-src ] || ln -s /source/fetched-sources/boost-1.89.0 build/_deps/boost-src
[ -e build/_deps/json-src ] || ln -s /source/fetched-sources/nlohmann-json-3.11.3 build/_deps/json-src
ninja -C build -j"${SOURCE_BUILD_JOBS:-1}"
bash /project/packaging/package-deb.sh "$system"
