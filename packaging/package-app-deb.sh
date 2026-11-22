#!/usr/bin/env bash
# Build the screen-spawner .deb: the app itself, for every Debian and Ubuntu
# release (Architecture: all). Hermes comes from its own package,
# hermes-screen-spawner, and EVDI from the system's evdi-dkms.
# Usage: package-app-deb.sh VERSION [OUTPUT_DIR]
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
version=${1:?version required, for example 1.0.0}
here="$(cd "$(dirname "$0")/.." && pwd)"
out=${2:-$here/packages-app}
# The package revision: a new build of the same app version (PKG_RELEASE).
release=${PKG_RELEASE:-1}
# The Hermes package this app version is tested with.
hermes_min=0.5.1+ss0.2.0~

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
root="$stage/root"
mkdir -p "$root/DEBIAN"
"$here/packaging/stage-app.sh" "$here" "$root"
chmod 755 "$root" "$root/DEBIAN"
doc="$root/usr/share/doc/screen-spawner"
gzip -9n -c "$here/CHANGELOG.md" > "$doc/changelog.gz"
cat > "$doc/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: Screen Spawner
Source: https://github.com/itkawa/screen-spawner

Files: *
Copyright: itkawa
License: GPL-3.0-only
 On Debian systems, the full text of the GNU General Public License
 version 3 is in /usr/share/common-licenses/GPL-3.
EOF
chmod 644 "$doc/changelog.gz" "$doc/copyright"

size=$(du -sk --exclude=DEBIAN "$root" | cut -f1)
cat > "$root/DEBIAN/control" <<EOF
Package: screen-spawner
Version: $version-$release
Architecture: all
Maintainer: itkawa <10118073+itkawa@users.noreply.github.com>
Installed-Size: $size
Depends: hermes-screen-spawner (>= $hermes_min), evdi-dkms, kmod, python3, python3-gi, gir1.2-gtk-3.0, gir1.2-ayatanaappindicator3-0.1, x11-xserver-utils, pkexec | policykit-1
Recommends: linux-headers-generic | linux-headers-amd64, intel-media-va-driver | intel-media-va-driver-non-free
Suggests: gnome-shell-extension-appindicator | gnome-shell-extension-ubuntu-appindicators
Section: x11
Priority: optional
Homepage: https://github.com/itkawa/screen-spawner
Description: Android tablet or phone as a second monitor over Wi-Fi
 Screen Spawner turns an Android tablet or phone into a wireless second,
 third or further monitor for Linux through the standard Moonlight app,
 extended or mirrored, with touch. It runs a patched Hermes streaming
 server with EVDI virtual displays, one for each connected device.
EOF

cat > "$root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
# Screen Spawner: EVDI with four devices at once, loaded now and at boot; the
# udev rule and the safe start take effect now.
set -e
CONFIG=/etc/modprobe.d/evdi.conf
MARK=/var/lib/screen-spawner/evdi.conf.created
if [ "$1" = configure ]; then
    # 1 was the number before Screen Spawner 0.3.0; any other number was
    # chosen in the app (Devices at once) and stays.
    now=$(sed -n 's/^options evdi initial_device_count=\([0-9]\+\)$/\1/p' "$CONFIG" 2>/dev/null | tail -n 1)
    if [ -z "$now" ] || [ "$now" = 1 ]; then
        [ -e "$CONFIG" ] || { mkdir -p "${MARK%/*}"; : > "$MARK"; }
        echo "options evdi initial_device_count=4" > "$CONFIG"
    fi
    if ! grep -q '^evdi ' /proc/modules 2>/dev/null; then
        modprobe evdi 2>/dev/null || {
            echo "Screen Spawner: the EVDI driver could not be loaded now."
            echo "If it is not built for this kernel, install its headers:"
            echo "    sudo apt install linux-headers-$(uname -r)"
            echo "then restart the computer."
        }
    fi
    if [ -d /run/systemd/system ]; then
        systemctl daemon-reload || true
        udevadm control --reload || true
        udevadm trigger --subsystem-match=drm --action=change || true
    fi
fi
exit 0
EOF

cat > "$root/DEBIAN/postrm" <<'EOF'
#!/bin/sh
# Remove the EVDI settings the package created, on purge only; the safe
# start's mark goes on removal.
set -e
MARK=/var/lib/screen-spawner/evdi.conf.created
if [ "$1" = remove ] || [ "$1" = purge ]; then
    rm -f /var/lib/screen-spawner/boot-pending
    [ -d /run/systemd/system ] && systemctl daemon-reload || true
fi
if [ "$1" = purge ]; then
    if [ -e "$MARK" ]; then
        rm -f /etc/modprobe.d/evdi.conf "$MARK"
    fi
    rmdir /var/lib/screen-spawner 2>/dev/null || true
fi
exit 0
EOF
chmod 755 "$root/DEBIAN/postinst" "$root/DEBIAN/postrm"

mkdir -p "$out"
file="$out/screen-spawner_${version}-${release}_all.deb"
dpkg-deb --root-owner-group -Zxz --build "$root" "$file" >/dev/null
echo "$file"
