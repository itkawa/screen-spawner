#!/usr/bin/env bash
# Run inside the build container, from /build/Hermes.
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
system=${1:?system required}
if ! command -v file >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends file
fi
# Stage upstream's installed binary and assets, then retain only what the
# source installer uses. No upstream postinst, udev, polkit, sysusers or units.
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
install -Dm644 LICENSE "$stage/usr/share/doc/hermes-screen-spawner/copyright"
python3 /project/packaging/add-source-notice.py "$stage/usr/share/hermes/web"
install -m644 /project/packaging/THIRD-PARTY-NOTICES.md "$stage/usr/share/doc/hermes-screen-spawner/"
install -m644 node_modules/@lizardbyte/shared-web/LICENSE "$stage/usr/share/doc/hermes-screen-spawner/AGPL-3.0.txt"
if [ "$system" = ubuntu22.04 ]; then
    install -m644 /usr/share/doc/gcc-13-base/copyright "$stage/usr/share/doc/hermes-screen-spawner/GCC-RUNTIME-COPYRIGHT.txt"
fi
python3 /project/packaging/collect-license-notices.py \
    "$stage/usr/share/doc/hermes-screen-spawner/THIRD-PARTY-LICENSES.txt" \
    third-party build/_deps/boost-src build/_deps/json-src node_modules

cat > "$stage/usr/share/doc/hermes-screen-spawner/SOURCE" <<'SOURCE'
Modified Hermes 0.5.1 for Screen Spawner 0.1.1 (GPL-3.0).
Upstream: https://github.com/MrOz59/Hermes/tree/7de12dc2d1c009c5cc4c0e67b8c537ea9e370e99
Modifications and build scripts: https://github.com/itkawa/screen-spawner/tree/v0.1.1
See patches/evdi-fix.patch and packaging/ in that repository.
Full corresponding-source archive (including dependencies and build scripts):
https://github.com/itkawa/screen-spawner-hermes-builds/releases/download/v0.1.1/hermes-screen-spawner-0.1.1-source.tar.xz
Web UI shared-web component: AGPL-3.0-only; see AGPL-3.0.txt and notices.
SOURCE
binary=$(readlink -f "$stage/usr/bin/sunshine")
test -x "$binary"
objdump -p "$binary" | tee /build/needed.txt
if [ "$system" = ubuntu22.04 ]; then
    ! grep -E 'NEEDED.*(libstdc\+\+|libgcc_s)' /build/needed.txt
fi
strings "$binary" | grep -F /usr/share/hermes
[ -d "$stage/usr/share/hermes/web" ]
evdi=$(dpkg-query -W -f='${binary:Package}\n' 'libevdi[01]' 2>/dev/null | head -1)
# dlopen libraries are invisible to dpkg-shlibdeps. The 1.12 loader needs
# the unversioned libevdi.so link shipped by the jammy development package.
if [ "$system" = ubuntu22.04 ]; then evdi="$evdi, libevdi0-dev"; fi
runtime="$evdi, libavahi-client3, libavahi-common3, libxrandr2, libxfixes3, libxcb-shm0, libxcb-xfixes0, libgbm1, libva-drm2, libva-x11-2, libegl1, libgl1, libqt5svg5"
cat > /build/ScreenSpawnerCPack.cmake <<CONFIG
set(CPACK_GENERATOR "DEB")
set(CPACK_PACKAGE_NAME "hermes-screen-spawner")
set(CPACK_PACKAGE_VERSION "0.5.1+ss0.1.1~$system")
set(CPACK_PACKAGE_CONTACT "itkawa <10118073+itkawa@users.noreply.github.com>")
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "itkawa <10118073+itkawa@users.noreply.github.com>")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Hermes with the Screen Spawner EVDI patch")
set(CPACK_PACKAGE_DESCRIPTION "Hermes 0.5.1 modified for Screen Spawner 0.1.1. GPL-3.0.")
set(CPACK_PACKAGE_HOMEPAGE_URL "https://github.com/itkawa/screen-spawner")
set(CPACK_DEBIAN_PACKAGE_ARCHITECTURE "amd64")
set(CPACK_DEBIAN_PACKAGE_CONFLICTS "hermes")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "$runtime")
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
set(CPACK_INSTALLED_DIRECTORIES "$stage;/")
set(CPACK_PACKAGE_DIRECTORY "/build/cpack-artifacts")
set(CPACK_PACKAGE_FILE_NAME "hermes-screen-spawner_0.5.1+ss0.1.1_${system}_amd64")
set(CPACK_PACKAGING_INSTALL_PREFIX "/")
set(CPACK_STRIP_FILES ON)
CONFIG
cpack --config /build/ScreenSpawnerCPack.cmake -G DEB

install -m644 "/build/cpack-artifacts/hermes-screen-spawner_0.5.1+ss0.1.1_${system}_amd64.deb" /out/
