#!/usr/bin/env bash
# Test the DNF repository in a clean Fedora container: add it with
# install-repo.sh, install screen-spawner (signatures checked), upgrade to a
# newer version, remove.
# Usage: test-dnf-repo.sh IMAGE SITE1 SITE2   (SITE2 has a newer screen-spawner)
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
image=${1:?image} site1=${2:?site1} site2=${3:?site2}
port=${PORT:-8767}
serve="$(mktemp -d)"
ln -s "$(realpath "$site1")" "$serve/s1"
ln -s "$(realpath "$site2")" "$serve/s2"
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$serve" >/dev/null 2>&1 &
server=$!
trap 'kill $server 2>/dev/null; rm -rf "$serve"' EXIT
sleep 1

logs=${LOGS:-$(mktemp -d)}
mkdir -p "$logs"
docker run --rm --network host --memory=6g --cpus=4 -e PORT="$port" -v "$(realpath "$logs"):/logs" "$image" bash -euo pipefail -c '
base=http://127.0.0.1:$PORT
fail() { echo "FAIL: $*"; cp /tmp/*.log /logs/ 2>/dev/null || true; for f in /tmp/*.log; do echo "--- $f"; grep -v -E "^\[[0-9]+/[0-9]+\]" "$f" | tail -60; done; exit 1; }
# A real Fedora runs a Fedora kernel with its headers installed; the
# container runs the host kernel. Package scripts (DKMS) see the newest
# Fedora kernel instead, as after an update and a restart.
kernel=$(dnf -q repoquery --latest-limit 1 --qf "%{VERSION}-%{RELEASE}.%{ARCH}\n" kernel-devel | tail -n 1)
echo "Simulated kernel: $kernel"
mv /usr/bin/uname /usr/bin/uname.real
printf "#!/bin/sh\nif [ \"\$1\" = -r ]; then echo %s; else exec /usr/bin/uname.real \"\$@\"; fi\n" "$kernel" > /usr/bin/uname
chmod +x /usr/bin/uname
mkdir -p "/lib/modules/$kernel"
ln -sfn "/usr/src/kernels/$kernel" "/lib/modules/$kernel/build"
echo "=== install-repo.sh ==="
curl -fsSL $base/s1/install-repo.sh | SCREEN_SPAWNER_REPO_URL=$base/s1 sh
cat /etc/yum.repos.d/screen-spawner.repo
echo "=== dnf install screen-spawner ==="
dnf install -y screen-spawner > /tmp/install.log 2>&1 || { tail -40 /tmp/install.log; fail install; }
grep -i -E "screen spawner:|importing|imported|signature" /tmp/install.log | head -10 || true
v1=$(rpm -q --qf "%{VERSION}" screen-spawner)
echo "installed $v1, Hermes $(rpm -q hermes-screen-spawner)"
rpm -q --qf "%{NAME}: %{SIGPGP:pgpsig}%{RSAHEADER:pgpsig}\n" screen-spawner hermes-screen-spawner
rpm -q --qf "%{SIGPGP}%{RSAHEADER}%{OPENPGP}" screen-spawner 2>/dev/null | grep -qv "(none)" || true
test -x /usr/bin/screen-spawner || fail "no /usr/bin/screen-spawner"
test "$(readlink -f /usr/bin/screen-spawner)" = /usr/share/screen-spawner/app/screen-spawner || fail realpath
test -f /usr/share/applications/screen-spawner.desktop || fail desktop
test -f /usr/share/icons/hicolor/scalable/apps/screen-spawner.svg || fail icon
test "$(cat /usr/lib/modules-load.d/screen-spawner-evdi.conf)" = evdi || fail modules-load
grep -qx "options evdi initial_device_count=4" /etc/modprobe.d/evdi.conf || fail evdi.conf
rpm -q dkms-evdi >/dev/null || fail "no dkms-evdi"
dkms status evdi | grep -q installed || fail "EVDI not built by DKMS"
dkms status evdi
/usr/bin/sunshine --version > /tmp/version.txt 2>&1 || true
grep -m1 "Hermes version" /tmp/version.txt || fail "Hermes does not start"
python3 - <<PY || fail "python gi"
import gi
gi.require_version("Gtk", "3.0"); gi.require_version("AyatanaAppIndicator3", "0.1")
from gi.repository import Gtk, AyatanaAppIndicator3
import os
print("gi ok; packaged:", os.path.realpath("/usr/bin/screen-spawner").startswith("/usr/"))
PY
echo "=== upgrade ==="
sed -i "s|$base/s1|$base/s2|" /etc/yum.repos.d/screen-spawner.repo
dnf upgrade -y --refresh > /tmp/upgrade.log 2>&1 || { tail -30 /tmp/upgrade.log; fail upgrade; }
v2=$(rpm -q --qf "%{VERSION}" screen-spawner)
echo "upgraded $v1 -> $v2"
[ "$v1" != "$v2" ] || fail "not upgraded"
grep -qx "options evdi initial_device_count=4" /etc/modprobe.d/evdi.conf || fail "evdi.conf after upgrade"
test -e /var/lib/screen-spawner/evdi.conf.created || fail "marker lost on upgrade"
echo "=== remove ==="
dnf remove -y screen-spawner > /tmp/remove.log 2>&1 || { tail -20 /tmp/remove.log; fail remove; }
test ! -e /usr/bin/screen-spawner || fail "binary left"
test ! -e /usr/share/screen-spawner || fail "share left"
test ! -e /usr/lib/modules-load.d/screen-spawner-evdi.conf || fail "modules-load left"
test ! -e /etc/modprobe.d/evdi.conf || fail "evdi.conf left"
test ! -e /var/lib/screen-spawner || fail "state dir left"
# dnf remove also takes away the dependencies nothing else needs.
rpm -q hermes-screen-spawner >/dev/null 2>&1 && fail "Hermes left after remove" || true
rpm -q dkms-evdi >/dev/null 2>&1 && fail "dkms-evdi left after remove" || true
cp /tmp/*.log /logs/ 2>/dev/null || true
echo "=== OK ==="
'
