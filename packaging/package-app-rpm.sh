#!/usr/bin/env bash
# Build the screen-spawner .rpm for Fedora (noarch) in a fedora container.
# Hermes comes from its own package, hermes-screen-spawner, and EVDI from
# dkms-evdi (negativo17).
# Usage: package-app-rpm.sh VERSION [OUTPUT_DIR]
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
version=${1:?version required, for example 1.0.0}
here="$(cd "$(dirname "$0")/.." && pwd)"
out=${2:-$here/packages-app}
image=${FEDORA_IMAGE:-fedora:45}
mkdir -p "$out"
out="$(cd "$out" && pwd)"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
"$here/packaging/stage-app.sh" "$here" "$stage/root"
cp "$here/CHANGELOG.md" "$stage/root/usr/share/doc/screen-spawner/CHANGELOG.md"
chmod 644 "$stage/root/usr/share/doc/screen-spawner/CHANGELOG.md"
chmod 755 "$stage" "$stage/root"

# rpm versions cannot hold "-"; "~" sorts before the release, as in Debian.
cat > "$stage/screen-spawner.spec" <<EOF
Name:           screen-spawner
Version:        $version
Release:        1
Summary:        Android tablet or phone as a second monitor over Wi-Fi
License:        GPL-3.0-only
URL:            https://github.com/itkawa/screen-spawner
BuildArch:      noarch
Requires:       hermes-screen-spawner >= 0.5.1
Requires:       dkms-evdi
Requires:       kmod
Requires:       python3-gobject
Requires:       gobject-introspection
Requires:       gtk3
Requires:       libayatana-appindicator-gtk3
Requires:       xrandr
Requires:       polkit
Recommends:     kernel-devel
Recommends:     libva-intel-media-driver
# The top bar icon on plain GNOME; only where GNOME Shell is installed.
Recommends:     (gnome-shell-extension-appindicator if gnome-shell)

%description
Screen Spawner turns an Android tablet or phone into a wireless second,
third or further monitor for Linux through the standard Moonlight app,
extended or mirrored, with touch. It runs a patched Hermes streaming
server with EVDI virtual displays, one for each connected device.

%install
cp -a /stage/root/. %{buildroot}/

%post
# EVDI with four devices at once, loaded now and at boot. 1 was the number
# before Screen Spawner 0.3.0; any other number was chosen in the app
# (Devices at once) and stays.
CONFIG=/etc/modprobe.d/evdi.conf
MARK=/var/lib/screen-spawner/evdi.conf.created
now=\$(sed -n 's/^options evdi initial_device_count=\([0-9]\+\)\$/\1/p' "\$CONFIG" 2>/dev/null | tail -n 1)
if [ -z "\$now" ] || [ "\$now" = 1 ]; then
    [ -e "\$CONFIG" ] || { mkdir -p "\${MARK%/*}"; : > "\$MARK"; }
    echo "options evdi initial_device_count=4" > "\$CONFIG"
fi
if ! grep -q '^evdi ' /proc/modules 2>/dev/null; then
    modprobe evdi 2>/dev/null || {
        echo "Screen Spawner: the EVDI driver could not be loaded now."
        echo "If it is not built for this kernel, install its headers:"
        echo "    sudo dnf install kernel-devel-\$(uname -r)"
        echo "then restart the computer."
    }
fi
exit 0

%postun
# Removed, not upgraded: the EVDI settings the package created go too.
if [ "\$1" -eq 0 ]; then
    MARK=/var/lib/screen-spawner/evdi.conf.created
    if [ -e "\$MARK" ]; then
        rm -f /etc/modprobe.d/evdi.conf "\$MARK"
    fi
    rmdir /var/lib/screen-spawner 2>/dev/null || true
fi
exit 0

%files
%license /usr/share/doc/screen-spawner/THIRD-PARTY-NOTICES.md
/usr/bin/screen-spawner
/usr/share/screen-spawner
/usr/share/applications/screen-spawner.desktop
/usr/share/icons/hicolor/*/apps/screen-spawner*
/usr/lib/modules-load.d/screen-spawner-evdi.conf
%doc /usr/share/doc/screen-spawner/README.md
%doc /usr/share/doc/screen-spawner/CHANGELOG.md
%doc /usr/share/doc/screen-spawner/docs
EOF

docker run --rm --memory=4g --cpus=4 -v "$stage:/stage:ro" -v "$out:/out" "$image" bash -euo pipefail -c '
dnf install -y -q rpm-build >/dev/null
rpmbuild -bb --define "_topdir /tmp/rpm" --define "_rpmdir /tmp/rpm/out" /stage/screen-spawner.spec >/tmp/build.log 2>&1 || { tail -30 /tmp/build.log; exit 1; }
f=$(find /tmp/rpm/out -name "*.rpm")
cp $f /out/
chown '"$(id -u):$(id -g)"' /out/$(basename $f)
echo /out/$(basename $f)
' | sed "s|^/out|$out|"
