#!/usr/bin/env bash
# Build dependencies of Hermes on Fedora and Arch Linux, inside the build container.
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
. /etc/os-release
case "$ID" in
fedora)
    dnf -y install \
        gcc gcc-c++ make cmake ninja-build git curl wget xz file which python3 rpm-build \
        openssl-devel libcurl-devel miniupnpc-devel libdrm-devel libevdev-devel libcap-devel \
        libva-devel libX11-devel libxcb-devel libXfixes-devel libXrandr-devel libXtst-devel \
        libXi-devel libXinerama-devel libXcursor-devel opus-devel pulseaudio-libs-devel \
        systemd-devel numactl-devel mesa-libgbm-devel mesa-libGL-devel libgudev-devel \
        wayland-devel wayland-protocols-devel qt6-qtbase-devel qt6-qtsvg-devel ;;
arch)
    pacman -Syu --noconfirm --needed \
        base-devel git curl wget xz file which python cmake ninja \
        openssl curl miniupnpc libdrm libevdev libcap libva libx11 libxcb libxfixes \
        libxrandr libxtst libxi libxinerama libxcursor opus libpulse systemd numactl \
        mesa libglvnd wayland wayland-protocols qt6-base qt6-svg ;;
*)
    echo "Unsupported build system: $ID" >&2; exit 1 ;;
esac
# Node is confined to the build image, as for the Debian packages.
curl -fsSL --retry 3 --connect-timeout 20 --max-time 120 https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt -o /tmp/node-sha256
node_file=$(awk '$2 ~ /linux-x64.tar.xz$/ {print $2}' /tmp/node-sha256)
curl -fsSL --retry 3 --connect-timeout 20 --max-time 300 "https://nodejs.org/dist/latest-v22.x/$node_file" -o "/tmp/$node_file"
(cd /tmp && grep " $node_file\$" node-sha256 | sha256sum -c -)
tar -xJf "/tmp/$node_file" -C /usr/local --strip-components=1
rm -f "/tmp/$node_file" /tmp/node-sha256
