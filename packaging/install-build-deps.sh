#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    build-essential pkg-config git wget curl ca-certificates xz-utils \
    libssl-dev libcurl4-openssl-dev libminiupnpc-dev libdrm-dev libevdev-dev \
    libcap-dev libva-dev libva-drm2 libx11-dev libopus-dev libxfixes-dev \
    libxrandr-dev libxcb-shm0-dev libxcb-xfixes0-dev libpulse-dev \
    libsystemd-dev libnuma-dev libgbm-dev qtbase5-dev libqt5svg5-dev \
    ninja-build dpkg-dev file cmake python3 python3-pip gnupg
if apt-cache show libevdi-dev >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends libevdi1 libevdi-dev
else
    apt-get install -y --no-install-recommends libevdi0 libevdi0-dev
fi
. /etc/os-release
if [ "$ID:$VERSION_ID" = ubuntu:22.04 ]; then
    fingerprint=C8EC952E2A0E1FBDC5090F6A2C277A0A352154E5
    curl --fail --location --retry 3 --connect-timeout 20 --max-time 120 \
        "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$fingerprint" -o /tmp/toolchain.asc
    actual=$(gpg --batch --show-keys --with-colons /tmp/toolchain.asc | awk -F: '$1 == "fpr" {print $10; exit}')
    [ "$actual" = "$fingerprint" ]
    gpg --batch --yes --dearmor -o /usr/share/keyrings/ss-toolchain.gpg /tmp/toolchain.asc
    echo 'deb [signed-by=/usr/share/keyrings/ss-toolchain.gpg] https://ppa.launchpadcontent.net/ubuntu-toolchain-r/test/ubuntu jammy main' > /etc/apt/sources.list.d/ss-toolchain.list
    apt-get update
    apt-get install -y gcc-13 g++-13
    pip3 install --no-cache-dir 'cmake==3.31.6'
fi
# Node is confined to the build image; nothing is installed on the host.
curl -fsSL --retry 3 --connect-timeout 20 --max-time 120 https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt -o /tmp/node-sha256
node_file=$(awk '$2 ~ /linux-x64.tar.xz$/ {print $2}' /tmp/node-sha256)
curl -fsSL --retry 3 --connect-timeout 20 --max-time 300 "https://nodejs.org/dist/latest-v22.x/$node_file" -o "/tmp/$node_file"
(cd /tmp && grep " $node_file\$" node-sha256 | sha256sum -c -)
tar -xJf "/tmp/$node_file" -C /usr/local --strip-components=1
rm -f "/tmp/$node_file" /tmp/node-sha256
