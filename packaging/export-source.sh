#!/usr/bin/env bash
set -euo pipefail
src=/build/Hermes
stage=/export/hermes-screen-spawner-0.1.1-source
mkdir -p "$stage/Hermes" "$stage/build-support"
# Preserve exactly the patched sources and recursive submodule contents used.
# Build objects and Git databases are not Corresponding Source.
tar -C "$src" --exclude='./.git' --exclude='*/.git' --exclude='./build' --exclude='./node_modules' -cf - . | tar -C "$stage/Hermes" -xf -
mkdir -p "$stage/fetched-sources"
cp -a "$src/build/_deps/boost-src" "$stage/fetched-sources/boost-1.89.0"
cp -a "$src/build/_deps/json-src" "$stage/fetched-sources/nlohmann-json-3.11.3"
cp -a "$src/node_modules" "$stage/fetched-sources/npm-node_modules"
cp "$src/package-lock.json" "$stage/build-support/package-lock.ubuntu22.04.json"
git -c safe.directory="$src" -C "$src" submodule status --recursive > "$stage/build-support/HERMES-SUBMODULES.txt"
git -c safe.directory="$src" -C "$src" diff --binary HEAD > "$stage/build-support/ACTUAL-HERMES-CHANGES.patch"
cp -a /project/packaging "$stage/build-support/packaging"
cp -a /project/patches "$stage/build-support/patches"
cp /project/LICENSE "$stage/build-support/SCREEN-SPAWNER-LICENSE"
cp "$src/build/CMakeCache.txt" "$stage/build-support/CMakeCache.ubuntu22.04.txt"
# Copying reproducible source files requires no root-owned output on the host.
chown -R "$EXPORT_UID:$EXPORT_GID" "$stage"
printf '\n=== shared-web and Vue source inventory ===\n'
find "$src/node_modules/@lizardbyte/shared-web" -maxdepth 3 -type f | sed -n '1,40p'
cat "$src/node_modules/@lizardbyte/shared-web/package.json"
cat "$src/node_modules/vue/package.json" | sed -n '1,55p'
