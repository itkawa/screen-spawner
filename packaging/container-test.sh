#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
system=$TEST_SYSTEM
[ "$system" != mint22 ] || system=ubuntu24.04
package=/packages/hermes-screen-spawner_0.5.1+ss0.1.1_${system}_amd64.deb
apt-get update
if [ "$TEST_MODE" = package ]; then
    # Minimal Docker images exclude most /usr/share/doc files during unpacking.
    # Keep package notices so this test can check their installed contents.
    for config in /etc/dpkg/dpkg.cfg /etc/dpkg/dpkg.cfg.d/*; do
        [ -f "$config" ] || continue
        sed -i '\|^[[:space:]]*path-exclude[=[:space:]].*/usr/share/doc|d' "$config"
    done
    apt-get install -y binutils python3
    dpkg-deb -I "$package"
    test "$(dpkg-deb -f "$package" Version)" = "0.5.1+ss0.1.1~$system"
    control=$(mktemp -d)
    dpkg-deb -e "$package" "$control"
    for script in preinst postinst prerm postrm; do test ! -e "$control/$script"; done
    test "$(dpkg-deb -f "$package" Maintainer)" = 'itkawa <10118073+itkawa@users.noreply.github.com>'
    test "$(dpkg-deb -f "$package" Conflicts)" = hermes
    test -z "$(dpkg-deb -f "$package" Provides)"
    test -z "$(dpkg-deb -f "$package" Replaces)"
    apt-get install -y "$package"
    dpkg -L hermes-screen-spawner | tee /tmp/ss-package-files
    ldd /usr/bin/sunshine | tee /tmp/ss-ldd
    ! grep -F 'not found' /tmp/ss-ldd
    python3 - <<'PYTHON'
import ctypes, os
libraries=['libavahi-common.so.3', 'libavahi-client.so.3', 'libXrandr.so.2',
           'libXfixes.so.3', 'libX11.so.6', 'libxcb-shm.so.0', 'libxcb.so.1',
           'libgbm.so.1', 'libva-drm.so.2', 'libva-x11.so.2', 'libEGL.so.1', 'libGL.so.1']
libraries.append('libevdi.so' if os.environ['TEST_SYSTEM']=='ubuntu22.04' else 'libevdi.so.1')
for lib in libraries:
    ctypes.CDLL(lib)
print('PASS: dynamically loaded runtime libraries')
PYTHON
    /usr/bin/sunshine --version
    strings "$(readlink -f /usr/bin/sunshine)" | grep -F /usr/share/hermes
    test -s /usr/share/hermes/web/index.html
    test -s /usr/share/doc/hermes-screen-spawner/AGPL-3.0.txt
    test -s /usr/share/doc/hermes-screen-spawner/THIRD-PARTY-NOTICES.md
    test -s /usr/share/doc/hermes-screen-spawner/THIRD-PARTY-LICENSES.txt
    python3 - <<'NOTICES'
from pathlib import Path
pages=list(Path('/usr/share/hermes/web').glob('*.html'))
assert len(pages)==8
for page in pages:
    text=page.read_text()
    assert text.count('id="screen-spawner-source-notice"')==1
    assert 'screen-spawner-hermes-builds/releases/download/v0.1.1/hermes-screen-spawner-0.1.1-source.tar.xz' in text
print('PASS: source offers on all 8 Web UI pages and original license notices')
NOTICES

    # Record package-owned files, not shared parent directories.
    while IFS= read -r path; do
        if [ -f "$path" ] || [ -L "$path" ]; then echo "$path"; fi
    done < /tmp/ss-package-files > /tmp/ss-owned-files
    apt-get remove -y hermes-screen-spawner
    while IFS= read -r path; do test ! -e "$path" && test ! -L "$path"; done < /tmp/ss-owned-files
    echo '=== PASS: package install, dependencies, version, assets and removal ==='
    exit
fi

# A container has no usable kernel modules or desktop. Simulate only kernel
# loading/reporting, never use --privileged or the host's /lib/modules.
apt-get install -y sudo git curl ca-certificates kmod
headers=linux-headers-generic
[ "$system" != debian13 ] || headers=linux-headers-amd64
kernel=$(apt-cache depends "$headers" | awk '/Depends: linux-headers-/ {sub("linux-headers-", "", $2); print $2; exit}')
test -n "$kernel"
cat > /usr/local/bin/uname <<UNAME
#!/bin/sh
if [ "\$1" = -r ]; then echo '$kernel'; else exec /usr/bin/uname "\$@"; fi
UNAME
cat > /usr/local/bin/modprobe <<'MODPROBE'
#!/bin/sh
if [ "$1" = evdi ]; then touch /tmp/ss-evdi-loaded; exit 0; fi
if [ "$1" = -r ] && [ "$2" = evdi ]; then rm -f /tmp/ss-evdi-loaded; exit 0; fi
exec /usr/sbin/modprobe "$@"
MODPROBE
cat > /usr/local/bin/lsmod <<'LSMOD'
#!/bin/sh
echo 'Module Size Used by'
if [ -f /tmp/ss-evdi-loaded ]; then echo 'evdi 1 0'; fi
exit 0
LSMOD
chmod +x /usr/local/bin/{uname,modprobe,lsmod}
if ! id tester >/dev/null 2>&1; then useradd -m -s /bin/bash tester; fi
echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester
cp -r /project /home/tester/screen-spawner
chown -R tester:tester /home/tester/screen-spawner
# The test image's original snap wrapper is used only on the source path.
runuser -u tester -- env HOME=/home/tester bash -c '
    set -e
    cd /home/tester/screen-spawner
    if [ "$1" = source ]; then
        BUILD_JOBS=1 ./install.sh --build-from-source
        test -d "$HOME/Apollo-Linux/.git"
    else
        SCREEN_SPAWNER_PACKAGE_DIR=/packages ./install.sh
        test ! -e "$HOME/Apollo-Linux"
        test ! -e "$HOME/.nvm"
        test ! -e "$HOME/.npm"
        grep -qxF "apt"$'"'"'\t'"'"'"hermes-screen-spawner" "$HOME/.local/state/screen-spawner/installed.list"
        grep -qxF "Exec=\"/usr/bin/sunshine\"" "$HOME/.local/share/applications/hermes.desktop"
    fi
    grep -qxF "stream_audio = false" "$HOME/.config/hermes/hermes.conf"
    printf "y\n" | ./uninstall.sh
    test ! -e "$HOME/.local/state/screen-spawner/installed.list"
    test ! -e "$HOME/.local/share/applications/hermes.desktop"
    test ! -e "$HOME/Apollo-Linux"
    test -d "$HOME/.config/hermes"
' bash "$TEST_MODE"
test ! -e /usr/bin/sunshine
test ! -e /usr/share/hermes
test ! -e /etc/modprobe.d/evdi.conf
! grep -qxF evdi /etc/modules
! dpkg-query -W -f='${db:Status-Abbrev}' hermes-screen-spawner 2>/dev/null | grep -q '^ii'
echo "=== PASS: installer $TEST_MODE and complete manifest removal ==="
