#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Makes the corresponding-source archive of a new package version from the
# previous one when only Screen Spawner's Hermes patch and build scripts changed
# (same Hermes revision, submodules, Boost/json/npm and codec sources).
#
# Usage: refresh-source-archive.sh OLD_ARCHIVE OLD_VERSION NEW_VERSION PACKAGE_DIR
# PACKAGE_DIR holds the new DEBs; the new archive is written there.
set -euo pipefail
old_archive=$(realpath "$1"); old=$2; new=$3; out=$(realpath "$4")
project=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "$out/.source-XXXXXX")
trap 'rm -rf "$work"' EXIT
tar -xJf "$old_archive" -C "$work"
mv "$work/hermes-screen-spawner-$old-source" "$work/hermes-screen-spawner-$new-source"
stage=$work/hermes-screen-spawner-$new-source

# Hermes: take the old patch out and put the new one in.
patch -s -p1 -R -d "$stage/Hermes" < "$stage/build-support/patches/evdi-fix.patch"
patch -s -p1 -d "$stage/Hermes" < "$project/patches/evdi-fix.patch"
find "$stage/Hermes" -name '*.orig' -delete

# Build control files from this checkout.
rm -rf "$stage/build-support/packaging" "$stage/build-support/patches"
cp -a "$project/packaging" "$stage/build-support/packaging"
cp -a "$project/patches" "$stage/build-support/patches"
for name in install.sh uninstall.sh README.md CHANGELOG.md LICENSE; do
    cp "$project/$name" "$stage/build-support/$name"
done
cp "$project/LICENSE" "$stage/build-support/SCREEN-SPAWNER-LICENSE"
# The patch body is exactly what differs from the upstream revision.
sed -n '/^diff --git /,$p' "$project/patches/evdi-fix.patch" > "$stage/build-support/ACTUAL-HERMES-CHANGES.patch"

# Version references in the archive's own descriptions.
sed -i "s/Screen Spawner $old/Screen Spawner $new/g; s#/v$old/#/v$new/#g; s/hermes-screen-spawner-$old-source/hermes-screen-spawner-$new-source/g" \
    "$stage/README-SOURCE.md"
python3 - "$stage/SOURCE-MANIFEST.json" "$old" "$new" <<'PY'
import json, sys, datetime
path, old, new = sys.argv[1:]
m = json.load(open(path))
m['release'] = f'Screen Spawner {new}'
m['modified_on'] = datetime.date.today().isoformat()
m['source_offer'] = m['source_offer'].replace(f'v{old}', f'v{new}').replace(f'-{old}-source', f'-{new}-source')
open(path, 'w').write(json.dumps(m, indent=2, ensure_ascii=False) + '\n')
PY
cat >> "$stage/README-SOURCE.md" <<EOF

## Changes since $old

Only \`patches/evdi-fix.patch\` and the build scripts changed; the Hermes revision,
submodules, Boost, nlohmann/json, npm packages and codec sources are the same as in
$old. \`build-support/OFFLINE-REBUILD-VALIDATION.txt\` describes the offline rebuild
check made for $old with these same dependency sources.
EOF

(cd "$out" && sha256sum hermes-screen-spawner_*+ss${new}_*_amd64.deb) > "$stage/BINARY-SHA256SUMS"

# Nothing of the old version may remain in our own files.
if grep -rln --exclude-dir=fetched-sources --exclude=CHANGELOG.md --exclude=OFFLINE-REBUILD-VALIDATION.txt --exclude=README-SOURCE.md \
        -e "ss$old" -e "v$old/" -e "Screen Spawner $old" "$stage"; then
    echo "ERROR: references to $old remain (listed above)." >&2
    exit 1
fi
tar -C "$work" --sort=name --owner=0 --group=0 --numeric-owner -cf - "hermes-screen-spawner-$new-source" \
    | xz -T2 -6 > "$out/.hermes-screen-spawner-$new-source.tar.xz"
mv "$out/.hermes-screen-spawner-$new-source.tar.xz" "$out/hermes-screen-spawner-$new-source.tar.xz"
ls -la "$out/hermes-screen-spawner-$new-source.tar.xz"
