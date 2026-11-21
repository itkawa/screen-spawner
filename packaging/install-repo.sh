#!/bin/sh
# Add the Screen Spawner package repository to this system, so that
# Screen Spawner installs and updates with the system's package manager.
#   curl -fsSL https://itkawa.github.io/screen-spawner-packages/install-repo.sh | sudo sh
# Then, on Ubuntu, Linux Mint and Debian:  sudo apt install screen-spawner
#      on Fedora:                          sudo dnf install screen-spawner
# Files it adds, and nothing else:
#   Ubuntu, Mint, Debian:
#     /usr/share/keyrings/screen-spawner-packages.gpg   the signing key
#     /etc/apt/sources.list.d/screen-spawner.sources    the repository
#   Fedora:
#     /etc/yum.repos.d/screen-spawner.repo              the repository
#     /etc/yum.repos.d/screen-spawner-evdi.repo         EVDI from negativo17
#   and installs the running kernel's headers (kernel-devel) if they are
#   missing, which EVDI is built against.
# To remove the repository, delete them.
# On Arch Linux, use install.sh from the Screen Spawner repository.
# SPDX-License-Identifier: GPL-3.0-only
set -eu
URL=${SCREEN_SPAWNER_REPO_URL:-https://itkawa.github.io/screen-spawner-packages}

if [ "$(id -u)" != 0 ]; then
    echo "Run it with sudo:" >&2
    echo "    curl -fsSL $URL/install-repo.sh | sudo sh" >&2
    exit 1
fi
[ -r /etc/os-release ] || { echo "This system is not recognized." >&2; exit 1; }
. /etc/os-release

download() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        echo "Neither curl nor wget is installed." >&2
        return 1
    fi
}

add_apt() {
    KEYRING=/usr/share/keyrings/screen-spawner-packages.gpg
    SOURCES=/etc/apt/sources.list.d/screen-spawner.sources
    # Ubuntu and systems built on it (Linux Mint, Pop!_OS, Zorin) name their
    # Ubuntu release in UBUNTU_CODENAME; Debian in VERSION_CODENAME.
    suite=${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}
    case "$suite" in
        jammy|noble|resolute|trixie) ;;
        *)
            echo "There are no Screen Spawner packages for ${PRETTY_NAME:-this system}." >&2
            echo "Supported: Ubuntu 22.04, 24.04 and 26.04, Linux Mint 22, Debian 13, Fedora 45." >&2
            exit 1 ;;
    esac
    if [ "$(dpkg --print-architecture)" != amd64 ]; then
        echo "Screen Spawner packages are for amd64 (x86_64) computers only." >&2
        exit 1
    fi
    echo "Adding the Screen Spawner repository for $suite..."
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    download "$URL/screen-spawner-packages.gpg" "$tmp"
    install -m 644 "$tmp" "$KEYRING"
    cat > "$SOURCES" <<EOF
Types: deb
URIs: $URL/apt
Suites: $suite
Components: main
Architectures: amd64
Signed-By: $KEYRING
EOF
    chmod 644 "$SOURCES"
    apt-get update
    echo
    echo "Done. Now install Screen Spawner:"
    echo "    sudo apt install screen-spawner"
}

add_dnf() {
    case "${VERSION_ID:-}" in
        45) ;;
        *)
            echo "There are no Screen Spawner packages for ${PRETTY_NAME:-this system}." >&2
            echo "Supported: Fedora 45; Ubuntu 22.04, 24.04 and 26.04, Linux Mint 22, Debian 13." >&2
            exit 1 ;;
    esac
    if [ "$(uname -m)" != x86_64 ]; then
        echo "Screen Spawner packages are for x86_64 computers only." >&2
        exit 1
    fi
    echo "Adding the Screen Spawner repository for Fedora $VERSION_ID..."
    cat > /etc/yum.repos.d/screen-spawner.repo <<EOF
[screen-spawner]
name=Screen Spawner
baseurl=$URL/rpm/fedora/\$releasever/\$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$URL/screen-spawner-packages.asc
EOF
    # Fedora has no EVDI package; the negativo17 repository has one, built
    # for each Fedora release. Only the EVDI packages are taken from it, so
    # it never replaces anything else on the system.
    if [ ! -e /etc/yum.repos.d/screen-spawner-evdi.repo ]; then
        cat > /etc/yum.repos.d/screen-spawner-evdi.repo <<'EOF'
[screen-spawner-evdi]
name=EVDI from negativo17 Multimedia, for Screen Spawner
baseurl=https://negativo17.org/repos/multimedia/fedora-$releasever/$basearch/
enabled=1
gpgcheck=1
gpgkey=https://negativo17.org/repos/RPM-GPG-KEY-slaanesh
includepkgs=dkms-evdi,libevdi
EOF
    fi
    chmod 644 /etc/yum.repos.d/screen-spawner.repo /etc/yum.repos.d/screen-spawner-evdi.repo
    # DKMS builds EVDI while dkms-evdi installs, and dnf may install it before
    # the kernel headers: they have to be there first.
    if ! rpm -q "kernel-devel-$(uname -r)" >/dev/null 2>&1; then
        echo "Installing the headers of the running kernel, needed to build EVDI..."
        if ! dnf install -y "kernel-devel-$(uname -r)"; then
            echo "The headers of the running kernel ($(uname -r)) are not available." >&2
            echo "Update the system (sudo dnf upgrade), restart, and run this again." >&2
            exit 1
        fi
    fi
    echo
    echo "Done. Now install Screen Spawner:"
    echo "    sudo dnf install screen-spawner"
    echo "dnf asks once to accept the signing keys of both repositories."
}

if command -v apt-get >/dev/null 2>&1 && command -v dpkg >/dev/null 2>&1; then
    add_apt
elif command -v dnf >/dev/null 2>&1; then
    add_dnf
elif command -v pacman >/dev/null 2>&1; then
    echo "There is no package repository for Arch Linux yet. Install with install.sh:"
    echo "    git clone https://github.com/itkawa/screen-spawner"
    echo "    cd screen-spawner && ./install.sh"
    exit 0
else
    echo "This system has neither apt nor dnf." >&2
    exit 1
fi
