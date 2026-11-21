#!/usr/bin/env bash
# Test the APT repository in a clean container: add it with install-repo.sh,
# install screen-spawner, upgrade to a newer version, remove and purge.
# Usage: test-apt-repo.sh IMAGE SITE1 SITE2
#   SITE1, SITE2  two built repositories (build-apt-repo.sh), SITE2 with a
#                 newer screen-spawner. Served over http on the host.
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
image=${1:?image} site1=${2:?site1} site2=${3:?site2}
port=${PORT:-8765}
serve="$(mktemp -d)"
ln -s "$(realpath "$site1")" "$serve/s1"
ln -s "$(realpath "$site2")" "$serve/s2"
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$serve" >/dev/null 2>&1 &
server=$!
trap 'kill $server 2>/dev/null; rm -rf "$serve"' EXIT
sleep 1

docker run --rm --network host --memory=6g --cpus=4 -e PORT="$port" "$image" bash -euo pipefail -c '
export DEBIAN_FRONTEND=noninteractive
base=http://127.0.0.1:$PORT
fail() { echo "FAIL: $*"; exit 1; }
apt-get update -qq
apt-get install -y -qq curl ca-certificates >/dev/null
echo "=== install-repo.sh ==="
curl -fsSL $base/s1/install-repo.sh | SCREEN_SPAWNER_REPO_URL=$base/s1 sh
grep -q "Suites: " /etc/apt/sources.list.d/screen-spawner.sources
cat /etc/apt/sources.list.d/screen-spawner.sources
echo "=== apt install screen-spawner ==="
apt-get install -y screen-spawner > /tmp/install.log 2>&1 || { tail -40 /tmp/install.log; fail install; }
grep -i -E "screen spawner:|evdi" /tmp/install.log | tail -8 || true
v1=$(dpkg-query -W -f="\${Version}" screen-spawner)
echo "installed $v1, Hermes $(dpkg-query -W -f="\${Version}" hermes-screen-spawner)"
test -x /usr/bin/screen-spawner || fail "no /usr/bin/screen-spawner"
test "$(readlink -f /usr/bin/screen-spawner)" = /usr/share/screen-spawner/app/screen-spawner || fail realpath
test -f /usr/share/applications/screen-spawner.desktop || fail desktop
test -f /usr/share/icons/hicolor/scalable/apps/screen-spawner.svg || fail icon
test "$(cat /usr/lib/modules-load.d/screen-spawner-evdi.conf)" = evdi || fail modules-load
grep -qx "options evdi initial_device_count=4" /etc/modprobe.d/evdi.conf || fail evdi.conf
dpkg -s evdi-dkms >/dev/null || fail "no evdi-dkms"
/usr/bin/sunshine --version > /tmp/version.txt 2>&1 || true
grep -m1 "Hermes version" /tmp/version.txt || fail "Hermes does not start"
python3 - <<PY || fail "python gi"
import gi
gi.require_version("Gtk", "3.0"); gi.require_version("AyatanaAppIndicator3", "0.1")
from gi.repository import Gtk, AyatanaAppIndicator3
import os
print("gi ok; packaged:", os.path.realpath("/usr/bin/screen-spawner").startswith("/usr/"))
PY
python3 -c "import ast;ast.parse(open(\"/usr/share/screen-spawner/app/screen-spawner\").read())"
echo "=== upgrade ==="
sed -i "s|$base/s1|$base/s2|" /etc/apt/sources.list.d/screen-spawner.sources
apt-get update -qq
apt-get upgrade -y > /tmp/upgrade.log 2>&1 || { tail -30 /tmp/upgrade.log; fail upgrade; }
v2=$(dpkg-query -W -f="\${Version}" screen-spawner)
echo "upgraded $v1 -> $v2"
[ "$v1" != "$v2" ] || fail "not upgraded"
grep -qx "options evdi initial_device_count=4" /etc/modprobe.d/evdi.conf || fail "evdi.conf after upgrade"
echo "=== remove ==="
apt-get remove -y screen-spawner >/dev/null
test ! -e /usr/bin/screen-spawner || fail "binary left"
test ! -e /usr/share/screen-spawner || fail "share left"
test ! -e /usr/lib/modules-load.d/screen-spawner-evdi.conf || fail "modules-load left"
test -e /etc/modprobe.d/evdi.conf || fail "evdi.conf removed before purge"
echo "=== purge ==="
apt-get purge -y screen-spawner >/dev/null
test ! -e /etc/modprobe.d/evdi.conf || fail "evdi.conf left after purge"
test ! -e /var/lib/screen-spawner || fail "state dir left"
# Hermes and EVDI came in as dependencies: autoremove takes them away.
# Simulated: a real autoremove in a container also removes base packages
# whose scripts need a real system.
apt-get -s autoremove > /tmp/autoremove.txt 2>&1 || true
if ! grep -q "^Remv hermes-screen-spawner " /tmp/autoremove.txt; then
    grep -E "^Remv|kept|E:" /tmp/autoremove.txt | head -20
    apt-mark showauto | grep -E "hermes|evdi" || echo "hermes is marked manual"
    apt-cache rdepends --installed hermes-screen-spawner
    fail "Hermes would stay after autoremove"
fi
grep -q "^Remv evdi-dkms " /tmp/autoremove.txt || fail "evdi-dkms would stay after autoremove"
echo "=== OK ==="
'
