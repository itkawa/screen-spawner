#!/usr/bin/env bash
# Test the AUR packages in a clean Arch Linux container, the way an AUR
# helper (yay) installs them: evdi-dkms from the AUR, hermes-screen-spawner-bin
# and screen-spawner from the prepared PKGBUILDs, all built with makepkg.
# Then upgrade (pkgrel 2) and remove with pacman -Rns.
# Usage: test-aur.sh AUR_DIR1 AUR_DIR2 HERMES_PKG
#   AUR_DIR1, AUR_DIR2  aur-prepare.sh output, AUR_DIR2 with pkgrel 2;
#                       each screen-spawner/ holds its source tarball.
#   HERMES_PKG          the hermes-screen-spawner .pkg.tar.zst of the release
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
aur1=$(realpath "${1:?}") aur2=$(realpath "${2:?}") hermes=$(realpath "${3:?}")
logs=${LOGS:-$(mktemp -d)}
mkdir -p "$logs"
docker run --rm --memory=6g --cpus=4 -v "$aur1:/aur1:ro" -v "$aur2:/aur2:ro" \
    -v "$hermes:/hermes/$(basename "$hermes"):ro" -v "$(realpath "$logs"):/logs" \
    archlinux:latest bash -euo pipefail -c '
fail() { echo "FAIL: $*"; cp /tmp/*.log /logs/ 2>/dev/null || true; tail -40 /tmp/*.log 2>/dev/null; exit 1; }
pacman -Syu --noconfirm --needed -q base-devel git sudo linux-headers > /tmp/base.log 2>&1 || fail base
useradd -m builder
echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder
# A real Arch runs the linux kernel with its headers; the container runs the
# host kernel. Package scripts (DKMS) see the Arch kernel instead.
v=$(pacman -Q linux-headers | cut -d" " -f2); base=${v%-*}; rel=${v##*-}
kernel="${base%.arch*}-arch${base##*.arch}-$rel"
echo "Simulated kernel: $kernel"
mv /usr/bin/uname /usr/bin/uname.real
printf "#!/bin/sh\nif [ \"\$1\" = -r ]; then echo %s; else exec /usr/bin/uname.real \"\$@\"; fi\n" "$kernel" > /usr/bin/uname
chmod +x /usr/bin/uname
mkdir -p "/usr/lib/modules/$kernel/kernel"

build() {  # build() DIR: makepkg as the builder, in a writable copy
    rm -rf /build; cp -r "$1" /build; chown -R builder /build
    (cd /build && runuser -u builder -- makepkg --syncdeps --noconfirm --needed) >> /tmp/build.log 2>&1 || fail "makepkg $1"
}
echo "=== evdi-dkms from the AUR ==="
runuser -u builder -- git clone -q --depth 1 https://aur.archlinux.org/evdi-dkms.git /home/builder/evdi-dkms
(cd /home/builder/evdi-dkms && runuser -u builder -- makepkg --syncdeps --noconfirm) > /tmp/evdi.log 2>&1 || fail evdi-dkms
pacman -U --noconfirm --asdeps $(ls /home/builder/evdi-dkms/evdi-dkms-[0-9]*.pkg.tar.zst) > /tmp/evdi-install.log 2>&1 || fail "evdi-dkms install"
dkms status evdi | grep -q installed || fail "EVDI not built by DKMS"
dkms status evdi
echo "=== hermes-screen-spawner-bin ==="
mkdir -p /tmp/h && cp -r /aur1/hermes-screen-spawner-bin/. /tmp/h/ && cp /hermes/* /tmp/h/
build /tmp/h
pacman -U --noconfirm --asdeps /build/hermes-screen-spawner-bin-*.pkg.tar.zst > /tmp/hermes.log 2>&1 || fail "hermes install"
echo "=== screen-spawner ==="
build /aur1/screen-spawner
pacman -U --noconfirm /build/screen-spawner-*.pkg.tar.zst > /tmp/install.log 2>&1 || fail install
cat /tmp/install.log | grep -i "screen spawner" || true
echo "installed $(pacman -Q screen-spawner), $(pacman -Q hermes-screen-spawner-bin)"
pacman -Qi hermes-screen-spawner-bin | grep -E "^Provides"
test -x /usr/bin/screen-spawner || fail "no /usr/bin/screen-spawner"
test "$(readlink -f /usr/bin/screen-spawner)" = /usr/share/screen-spawner/app/screen-spawner || fail realpath
test -f /usr/share/applications/screen-spawner.desktop || fail desktop
test -f /usr/share/icons/hicolor/scalable/apps/screen-spawner.svg || fail icon
test -f /usr/share/licenses/screen-spawner/LICENSE || fail license
test "$(cat /usr/lib/modules-load.d/screen-spawner-evdi.conf)" = evdi || fail modules-load
grep -qx "options evdi initial_device_count=4" /etc/modprobe.d/evdi.conf || fail evdi.conf
/usr/bin/sunshine --version > /tmp/version.txt 2>&1 || true
grep -m1 "Hermes version" /tmp/version.txt || { cat /tmp/version.txt; fail "Hermes does not start"; }
python3 - <<PY || fail "python gi"
import gi
gi.require_version("Gtk", "3.0"); gi.require_version("AyatanaAppIndicator3", "0.1")
from gi.repository import Gtk, AyatanaAppIndicator3
import os
print("gi ok; packaged:", os.path.realpath("/usr/bin/screen-spawner").startswith("/usr/"))
PY
echo "=== upgrade ==="
build /aur2/screen-spawner
pacman -U --noconfirm /build/screen-spawner-*.pkg.tar.zst > /tmp/upgrade.log 2>&1 || fail upgrade
echo "upgraded to $(pacman -Q screen-spawner)"
grep -qx "options evdi initial_device_count=4" /etc/modprobe.d/evdi.conf || fail "evdi.conf after upgrade"
test -e /var/lib/screen-spawner/evdi.conf.created || fail "marker lost on upgrade"
echo "=== remove ==="
pacman -Rns --noconfirm screen-spawner > /tmp/remove.log 2>&1 || fail remove
test ! -e /usr/bin/screen-spawner || fail "binary left"
test ! -e /usr/share/screen-spawner || fail "share left"
test ! -e /etc/modprobe.d/evdi.conf || fail "evdi.conf left"
test ! -e /var/lib/screen-spawner || fail "state dir left"
pacman -Q hermes-screen-spawner-bin >/dev/null 2>&1 && fail "Hermes left after remove" || true
pacman -Q evdi-dkms >/dev/null 2>&1 && fail "evdi-dkms left after remove" || true
cp /tmp/*.log /logs/ 2>/dev/null || true
echo "=== OK ==="
'
