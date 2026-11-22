#!/usr/bin/env bash
# Put the Screen Spawner app into ROOT the way every package installs it:
# the program in /usr/share/screen-spawner, a command in /usr/bin, the menu
# entry, icons, EVDI loading at boot, the safe start and the documentation.
# Shared by the deb, rpm and Arch packages.
# Usage: stage-app.sh SOURCE_TREE ROOT
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
here=${1:?source tree} root=${2:?root}
share="$root/usr/share/screen-spawner"
doc="$root/usr/share/doc/screen-spawner"

install -d "$share/app" "$root/usr/bin" "$root/usr/share/applications" \
    "$root/usr/lib/modules-load.d" "$doc/docs"
install -m 755 "$here/app/screen-spawner" "$share/app/screen-spawner"
cp -r "$here/app/icons" "$share/app/icons"
ln -s ../share/screen-spawner/app/screen-spawner "$root/usr/bin/screen-spawner"

# Icons in the standard place, for the menu and the window.
while IFS= read -r -d '' icon; do
    rel=${icon#"$here/app/icons/"}
    install -D -m 644 "$icon" "$root/usr/share/icons/$rel"
done < <(find "$here/app/icons/hicolor" -type f -print0)

cat > "$root/usr/share/applications/screen-spawner.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Screen Spawner
Comment=Use a tablet or phone as a second monitor
Keywords=tablet;phone;monitor;display;second;screen;moonlight;hermes;
Exec=screen-spawner
Icon=screen-spawner
Terminal=false
Categories=Utility;
StartupNotify=true
EOF

# evdi-dkms does not load the module at boot; systemd reads this file.
echo evdi > "$root/usr/lib/modules-load.d/screen-spawner-evdi.conf"

# The login screen waits for the real graphics card, not for EVDI's; and a
# start that did not reach the login screen is followed by one without EVDI.
sys="$here/app/system"
install -D -m 644 "$sys/72-screen-spawner-evdi.rules" "$root/usr/lib/udev/rules.d/72-screen-spawner-evdi.rules"
install -D -m 755 "$sys/screen-spawner-boot-guard" "$root/usr/lib/screen-spawner/screen-spawner-boot-guard"
units="$root/usr/lib/systemd/system"
install -D -m 644 "$sys/screen-spawner-safe-start.service" "$units/screen-spawner-safe-start.service"
install -D -m 644 "$sys/screen-spawner-start-ok.service" "$units/screen-spawner-start-ok.service"
install -d "$units/sysinit.target.wants" "$units/graphical.target.wants"
ln -s ../screen-spawner-safe-start.service "$units/sysinit.target.wants/screen-spawner-safe-start.service"
ln -s ../screen-spawner-start-ok.service "$units/graphical.target.wants/screen-spawner-start-ok.service"

install -m 644 "$here/README.md" "$doc/README.md"
install -m 644 "$here"/docs/* "$doc/docs/"
install -m 644 "$here/packaging/THIRD-PARTY-NOTICES.md" "$doc/THIRD-PARTY-NOTICES.md"

find "$root/usr" -type d -exec chmod 755 {} +
find "$root/usr" -type f ! -path '*/app/screen-spawner' ! -name screen-spawner-boot-guard -exec chmod 644 {} +
