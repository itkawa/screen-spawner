#!/usr/bin/env bash
# Read-only verification after the owner publishes the packages.
set -euo pipefail
project=$(cd "$(dirname "$0")/.." && pwd)
cd "$project"
. "$project/packaging/workspace.sh"
# Trust only this explicitly selected checkout, without changing global Git config.
git() { command git -c safe.directory="$project" "$@"; }
refs=$(git ls-remote origin refs/heads/main refs/tags/v0.3.1)
printf '%s\n' "$refs"
main=$(printf '%s\n' "$refs" | awk '$2=="refs/heads/main" {print $1}')
tag=$(printf '%s\n' "$refs" | awk '$2=="refs/tags/v0.3.1" {print $1}')
[ -n "$main" ] && [ "$main" = "$tag" ]
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 --connect-timeout 20 --max-time 60 \
    https://api.github.com/repos/itkawa/screen-spawner/releases/tags/v0.3.1 -o "$tmp/release.json"
python3 - "$tmp/release.json" <<'PY'
import json, sys
release=json.load(open(sys.argv[1]))
assert release['draft'] is False
assert release['tag_name']=='v0.3.1'
print('Release is public:', release['html_url'])
PY
# The builds release the installer downloads from: v0.2.2, all systems.
for builds in 0.2.2; do
    curl -fsSL --retry 3 --connect-timeout 20 --max-time 60 \
        "https://api.github.com/repos/itkawa/screen-spawner-packages/releases/tags/v$builds" -o "$tmp/builds-release.json"
    python3 - "$tmp/builds-release.json" "$builds" "$(wc -l < "$workspace/packages-$builds/SHA256SUMS")" <<'BUILDS'
import json, sys
release=json.load(open(sys.argv[1]))
assert release['draft'] is False
assert release['tag_name']=='v'+sys.argv[2]
assert len(release['assets'])==int(sys.argv[3])+1
print('Hermes builds release is public:', release['html_url'])
BUILDS
    while read -r checksum filename; do
        [[ "$filename" == hermes-screen-spawner* ]]
        curl -fL --retry 3 --connect-timeout 20 --max-time 600 \
            "https://github.com/itkawa/screen-spawner-packages/releases/download/v$builds/$filename" -o "$tmp/$filename"
        printf '%s  %s\n' "$checksum" "$tmp/$filename" | sha256sum -c -
        rm -f "$tmp/$filename"
    done < "$workspace/packages-$builds/SHA256SUMS"
    curl -fsSL --retry 3 --connect-timeout 20 --max-time 60 \
        "https://github.com/itkawa/screen-spawner-packages/releases/download/v$builds/SHA256SUMS" -o "$tmp/SHA256SUMS"
    cmp "$workspace/packages-$builds/SHA256SUMS" "$tmp/SHA256SUMS"
done
echo '=== PASS: matching main/tag, public release and every asset checksum ==='
