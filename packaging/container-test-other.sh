#!/usr/bin/env bash
# Package and installer checks on clean Fedora 45 and Arch Linux containers.
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
system=$TEST_SYSTEM
mode=$TEST_MODE
if [ "$system" = fedora45 ]; then
    package=/packages/hermes-screen-spawner-0.5.1-ss0.2.2.fc45.x86_64.rpm
    # The container image leaves out documentation; the package notices are checked.
    sed -i '/^tsflags=nodocs/d' /etc/dnf/dnf.conf 2>/dev/null || true
    dnf -y install sudo git curl kmod which binutils findutils python3 procps-ng util-linux shadow-utils
else
    package=/packages/hermes-screen-spawner-0.5.1.ss0.2.2-1-x86_64.pkg.tar.zst
    sed -i 's|^NoExtract.*usr/share/doc.*||' /etc/pacman.conf
    pacman -Syu --noconfirm --needed sudo git curl kmod which binutils findutils python procps-ng
fi

if [ "$mode" = package ]; then
    if [ "$system" = fedora45 ]; then
        test "$(rpm -qp --qf '%{NAME} %{VERSION}-%{RELEASE}' "$package")" = "hermes-screen-spawner 0.5.1-ss0.2.2.fc45"
        test "$(rpm -qp --qf '%{PACKAGER}%{VENDOR}' "$package" | grep -c itkawa)" = 1
        ! rpm -qp --scripts "$package" | grep -q .
        sed -n '/^\[screen-spawner-evdi\]/,$p' /project/install.sh | sed -n '1,/^REPO$/p' | sed '$d' > /etc/yum.repos.d/screen-spawner-evdi.repo
        grep -q includepkgs /etc/yum.repos.d/screen-spawner-evdi.repo
        dnf -y install "$package"
        rpm -ql hermes-screen-spawner > /tmp/ss-package-files
    else
        tar -xOf "$package" .PKGINFO | tee /tmp/pkginfo
        grep -qx 'pkgver = 0.5.1.ss0.2.2-1' /tmp/pkginfo
        ! tar -tf "$package" | grep -qx .INSTALL
        pacman -U --noconfirm --assume-installed evdi=1.15.1 "$package"
        pacman -Qlq hermes-screen-spawner > /tmp/ss-package-files
    fi
    ldd /usr/bin/sunshine | tee /tmp/ss-ldd
    ! grep -F 'not found' /tmp/ss-ldd
    /usr/bin/sunshine --version
    strings "$(readlink -f /usr/bin/sunshine)" | grep -F /usr/share/hermes
    strings "$(readlink -f /usr/bin/sunshine)" | grep -F 'xrandr --current'
    test -s /usr/share/hermes/web/index.html
    for f in AGPL-3.0.txt THIRD-PARTY-NOTICES.md THIRD-PARTY-LICENSES.txt SOURCE copyright; do
        test -s "/usr/share/doc/hermes-screen-spawner/$f"
    done
    grep -q 'releases/download/v0.2.2/hermes-screen-spawner-0.2.2-source.tar.xz' /usr/share/doc/hermes-screen-spawner/SOURCE
    test "$(grep -l 'screen-spawner-source-notice' /usr/share/hermes/web/*.html | wc -l)" = 8
    test "$(grep -l 'releases/download/v0.2.2/hermes-screen-spawner-0.2.2-source.tar.xz' /usr/share/hermes/web/*.html | wc -l)" = 8
    grep -q 'screen-spawner/blob/v0.3.1/packaging/THIRD-PARTY-NOTICES.md' /usr/share/hermes/web/index.html
    grep -q 'releases/download/v0.2.2/hermes-screen-spawner-0.2.2-source.tar.xz' /usr/share/doc/hermes-screen-spawner/THIRD-PARTY-NOTICES.md
    command -v xrandr && command -v gdbus
    while IFS= read -r path; do
        if [ -f "$path" ] || [ -L "$path" ]; then echo "$path"; fi
    done < /tmp/ss-package-files > /tmp/ss-owned-files
    if [ "$system" = fedora45 ]; then dnf -y remove hermes-screen-spawner; else pacman -R --noconfirm hermes-screen-spawner; fi
    while IFS= read -r path; do test ! -e "$path" && test ! -L "$path"; done < /tmp/ss-owned-files
    echo "=== PASS: $system package install, dependencies, version, assets and removal ==="
    exit
fi

# Installer: real DKMS build of EVDI for the distribution's current kernel;
# loading modules is simulated, as in the Debian checks.
if [ "$system" = fedora45 ]; then
    kernel=$(dnf -q repoquery --latest-limit 1 --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-devel | tail -n 1)
else
    v=$(pacman -Si linux-headers | awk -F': ' '/^Version/ {print $2}')
    base=${v%-*}; rel=${v##*-}
    kernel="${base%.arch*}-arch${base##*.arch}-$rel"
fi
test -n "$kernel"
echo "Simulated kernel: $kernel"
# Package scripts (DKMS) run with the system PATH, so the real uname is replaced.
mv /usr/bin/uname /usr/bin/uname.real
cat > /usr/bin/uname <<UNAME
#!/bin/sh
if [ "\$1" = -r ]; then echo '$kernel'; else exec /usr/bin/uname.real "\$@"; fi
UNAME
chmod +x /usr/bin/uname
# A real system has the kernel installed, which links its headers here.
if [ "$system" = fedora45 ]; then
    mkdir -p "/lib/modules/$kernel"
    ln -sfn "/usr/src/kernels/$kernel" "/lib/modules/$kernel/build"
else
    mkdir -p "/usr/lib/modules/$kernel/kernel"
fi
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
chmod +x /usr/local/bin/{modprobe,lsmod}
id tester >/dev/null 2>&1 || useradd -m -s /bin/bash tester
echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester
cp -r /project /home/tester/screen-spawner
chown -R tester:tester /home/tester/screen-spawner
packages_before="$(if [ "$system" = fedora45 ]; then rpm -qa --qf '%{NAME}\n'; else pacman -Qq; fi | sort)"
runuser -u tester -- env HOME=/home/tester PATH="/usr/local/bin:$PATH" bash -c '
    set -e
    cd /home/tester/screen-spawner
    SCREEN_SPAWNER_PACKAGE_DIR=/packages ./install.sh
    m="$HOME/.local/state/screen-spawner/installed.list"
    cat "$m"
    grep -qP "^(dnf|pacman)\thermes-screen-spawner$" "$m"
    grep -qxF "Exec=\"/usr/bin/sunshine\"" "$HOME/.local/share/applications/hermes.desktop"
    grep -qxF "stream_audio = false" "$HOME/.config/hermes/hermes.conf"
    test -x "$HOME/.local/share/screen-spawner/app/screen-spawner"
    python3 -c "import gi; gi.require_version(\"Gtk\", \"3.0\"); gi.require_version(\"AyatanaAppIndicator3\", \"0.1\"); from gi.repository import Gtk, AyatanaAppIndicator3; print(\"app libraries: ok\")"
    test "$(cat /etc/modprobe.d/evdi.conf)" = "options evdi initial_device_count=4"
    grep -qxF evdi /etc/modules-load.d/screen-spawner-evdi.conf
    test -f /etc/udev/rules.d/72-screen-spawner-evdi.rules || { echo "FAILED CHECK: test -f /etc/udev/rules.d/72-screen-spawner-evdi.rules"; ls -laR /etc/udev/rules.d /usr/local/lib/screen-spawner /usr/local/lib/systemd 2>&1 | head -30; exit 1; }
    test -x /usr/local/lib/screen-spawner/screen-spawner-boot-guard || { echo "FAILED CHECK: test -x /usr/local/lib/screen-spawner/screen-spawner-boot-guard"; ls -laR /etc/udev/rules.d /usr/local/lib/screen-spawner /usr/local/lib/systemd 2>&1 | head -30; exit 1; }
    grep -qxF "ExecStart=/usr/local/lib/screen-spawner/screen-spawner-boot-guard start" /usr/local/lib/systemd/system/screen-spawner-safe-start.service || { echo "FAILED CHECK: grep -qxF ExecStart=/usr/local/lib/screen-spawner/screen-spawner-boot-"; ls -laR /etc/udev/rules.d /usr/local/lib/screen-spawner /usr/local/lib/systemd 2>&1 | head -30; exit 1; }
    test -L /usr/local/lib/systemd/system/sysinit.target.wants/screen-spawner-safe-start.service || { echo "FAILED CHECK: test -L /usr/local/lib/systemd/system/sysinit.target.wants/screen-spawner-safe-s"; ls -laR /etc/udev/rules.d /usr/local/lib/screen-spawner /usr/local/lib/systemd 2>&1 | head -30; exit 1; }
    test -L /usr/local/lib/systemd/system/graphical.target.wants/screen-spawner-start-ok.service || { echo "FAILED CHECK: test -L /usr/local/lib/systemd/system/graphical.target.wants/screen-spawner-star"; ls -laR /etc/udev/rules.d /usr/local/lib/screen-spawner /usr/local/lib/systemd 2>&1 | head -30; exit 1; }
    dkms status | tee /tmp/dkms-status
    grep -q "^evdi/.*$(uname -r).*installed" /tmp/dkms-status
    printf "y\n" | ./uninstall.sh
    test ! -e "$m"
    test ! -e "$HOME/.local/share/applications/hermes.desktop"
    test ! -e "$HOME/.local/share/screen-spawner"
    test -d "$HOME/.config/hermes"
'
test ! -e /usr/bin/sunshine
test ! -e /usr/share/hermes
test ! -e /etc/modprobe.d/evdi.conf
test ! -e /etc/modules-load.d/screen-spawner-evdi.conf
test ! -e /etc/udev/rules.d/72-screen-spawner-evdi.rules
test ! -e /usr/local/lib/screen-spawner
test ! -e /usr/local/lib/systemd/system/screen-spawner-safe-start.service
test ! -e /usr/local/lib/systemd/system/sysinit.target.wants/screen-spawner-safe-start.service
test ! -e /usr/local/lib/systemd/system/graphical.target.wants/screen-spawner-start-ok.service
test ! -e /etc/yum.repos.d/screen-spawner-evdi.repo
if [ "$system" = fedora45 ]; then
    ! rpm -q dkms-evdi libevdi hermes-screen-spawner
    ! rpm -qi gpg-pubkey 2>/dev/null | grep -qi slaanesh
else
    ! pacman -Q evdi-dkms hermes-screen-spawner 2>/dev/null
    ! pacman -Q evdi-dkms-debug 2>/dev/null
fi
packages_after="$(if [ "$system" = fedora45 ]; then rpm -qa --qf '%{NAME}\n'; else pacman -Qq; fi | sort)"
left="$(comm -13 <(printf '%s\n' "$packages_before") <(printf '%s\n' "$packages_after"))"
echo "Packages left after uninstall that were not there before: ${left:-none}"
echo "=== PASS: $system installer and complete manifest removal ==="
