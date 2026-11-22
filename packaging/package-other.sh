#!/usr/bin/env bash
# Run inside the Fedora or Arch build container, from /build/Hermes: stage the
# built Hermes like package-deb.sh does and make an RPM or an Arch package.
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
system=${1:?system required}
builds=0.2.2
app=0.3.1
stage=/build/package-stage
rm -rf "$stage"
DESTDIR="$stage" cmake --install build
python3 - "$stage" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
for path in sorted(root.rglob('*'), key=lambda p: len(p.parts), reverse=True):
    rel=path.relative_to(root).as_posix()
    allowed=(rel in {'usr/share/icons/hicolor/scalable/apps/hermes.svg',
                     'usr/share/icons/hicolor/scalable/status/hermes-tray.svg',
                     'usr/share/icons/hicolor/scalable/status/hermes-playing.svg',
                     'usr/share/icons/hicolor/scalable/status/hermes-pausing.svg',
                     'usr/share/icons/hicolor/scalable/status/hermes-locked.svg'}
             or rel.startswith('usr/share/hermes/') or rel=='usr/share/hermes'
             or (rel.startswith('usr/bin/sunshine') and '/' not in rel[len('usr/bin/'):]))
    if path.is_dir() and not path.is_symlink():
        if not allowed:
            try: path.rmdir()
            except OSError: pass
    elif not allowed:
        path.unlink()
PY
doc="$stage/usr/share/doc/hermes-screen-spawner"
install -Dm644 LICENSE "$doc/copyright"
SS_BUILDS=$builds SS_APP=$app python3 /project/packaging/add-source-notice.py "$stage/usr/share/hermes/web"
install -m644 /project/packaging/THIRD-PARTY-NOTICES.md "$doc/"
install -m644 node_modules/@lizardbyte/shared-web/LICENSE "$doc/AGPL-3.0.txt"
python3 /project/packaging/collect-license-notices.py "$doc/THIRD-PARTY-LICENSES.txt" \
    third-party build/_deps/boost-src build/_deps/json-src node_modules
cat > "$doc/SOURCE" <<SOURCE
Modified Hermes 0.5.1 for Screen Spawner $app (GPL-3.0).
Upstream: https://github.com/MrOz59/Hermes/tree/7de12dc2d1c009c5cc4c0e67b8c537ea9e370e99
Modifications and build scripts: https://github.com/itkawa/screen-spawner/tree/v$app
See patches/evdi-fix.patch, patches/openssl4.patch and packaging/ in that repository.
Full corresponding-source archive (including dependencies and build scripts):
https://github.com/itkawa/screen-spawner-packages/releases/download/v$builds/hermes-screen-spawner-$builds-source.tar.xz
Web UI shared-web component: AGPL-3.0-only; see AGPL-3.0.txt and notices.
SOURCE
binary=$(readlink -f "$stage/usr/bin/sunshine")
test -x "$binary"
strings "$binary" | grep -F /usr/share/hermes
[ -d "$stage/usr/share/hermes/web" ]
mkdir -p /out
case "$system" in
fedora*)
    release="ss$builds.fc${system#fedora}"
    cat > /build/ScreenSpawnerCPack.cmake <<CONFIG
set(CPACK_GENERATOR "RPM")
set(CPACK_PACKAGE_NAME "hermes-screen-spawner")
set(CPACK_PACKAGE_VERSION "0.5.1")
set(CPACK_RPM_PACKAGE_RELEASE "$release")
set(CPACK_RPM_PACKAGE_RELEASE_DIST OFF)
set(CPACK_PACKAGE_CONTACT "itkawa <10118073+itkawa@users.noreply.github.com>")
set(CPACK_PACKAGE_VENDOR "itkawa")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Hermes with the Screen Spawner EVDI patch")
set(CPACK_PACKAGE_DESCRIPTION "Hermes 0.5.1 modified for Screen Spawner $app. GPL-3.0.")
set(CPACK_RPM_PACKAGE_LICENSE "GPL-3.0-only AND AGPL-3.0-only")
set(CPACK_RPM_PACKAGE_URL "https://github.com/itkawa/screen-spawner")
set(CPACK_RPM_PACKAGE_ARCHITECTURE "x86_64")
set(CPACK_RPM_PACKAGE_REQUIRES "libevdi, avahi-libs, xrandr, glib2, libva, mesa-libgbm, mesa-libEGL, mesa-libGL, qt6-qtsvg")
set(CPACK_RPM_PACKAGE_CONFLICTS "Hermes, hermes, Sunshine, sunshine")
set(CPACK_RPM_PACKAGE_AUTOREQ ON)
set(CPACK_RPM_EXCLUDE_FROM_AUTO_FILELIST_ADDITION "/usr/share/icons;/usr/share/icons/hicolor;/usr/share/icons/hicolor/scalable;/usr/share/icons/hicolor/scalable/apps;/usr/share/icons/hicolor/scalable/status;/usr/share/doc")
set(CPACK_INSTALLED_DIRECTORIES "$stage;/")
set(CPACK_PACKAGE_DIRECTORY "/build/cpack-artifacts")
set(CPACK_PACKAGE_FILE_NAME "hermes-screen-spawner-0.5.1-$release.x86_64")
set(CPACK_PACKAGING_INSTALL_PREFIX "/")
set(CPACK_STRIP_FILES ON)
CONFIG
    rm -rf /build/cpack-artifacts
    cpack --config /build/ScreenSpawnerCPack.cmake -G RPM
    artifact=$(find /build/cpack-artifacts -name "hermes-screen-spawner-0.5.1-$release.x86_64.rpm" | head -1)
    test -n "$artifact"
    install -m644 "$artifact" /out/ ;;
arch)
    id builder >/dev/null 2>&1 || useradd -m builder
    work=/build/arch-pkg
    rm -rf "$work"; mkdir -p "$work"
    cat > "$work/PKGBUILD" <<PKG
pkgname=hermes-screen-spawner
pkgver=0.5.1.ss$builds
pkgrel=1
pkgdesc="Hermes 0.5.1 modified for Screen Spawner $app"
arch=(x86_64)
url="https://github.com/itkawa/screen-spawner"
license=(GPL-3.0-only AGPL-3.0-only)
depends=(evdi avahi curl libcap libdrm libevdev libpulse libva libx11 libxcb libxfixes libxrandr libxtst
         miniupnpc numactl openssl opus qt6-base qt6-svg mesa libglvnd wayland xorg-xrandr glib2)
conflicts=(sunshine hermes)
options=(!debug)
package() {
    cp -a "$stage"/. "\$pkgdir"/
}
PKG
    chown -R builder: "$work"
    chmod -R a+rX "$stage"
    (cd "$work" && runuser -u builder -- makepkg --nodeps --force --noconfirm)
    install -m644 "$work"/hermes-screen-spawner-0.5.1.ss$builds-1-x86_64.pkg.tar.zst /out/ ;;
*)
    echo "Unknown system $system" >&2; exit 1 ;;
esac
