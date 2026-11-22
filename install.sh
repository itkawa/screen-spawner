#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

set -e

BUILD_FROM_SOURCE=0
for arg in "$@"; do
    case "$arg" in
        --build-from-source) BUILD_FROM_SOURCE=1 ;;
        -h|--help)
            echo "Usage: $0 [--build-from-source]"
            exit 0 ;;
        *) echo "ERROR: unknown option: $arg" >&2; exit 2 ;;
    esac
done

echo "=== Apollo-Linux / Hermes + EVDI installation ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$HOME/Apollo-Linux"
LAUNCHER="$HOME/.local/share/applications/hermes.desktop"

# The Hermes revision this setup was verified with, and the fix it needs
# to work with libevdi 1.12. Move the commit only after re-testing the patch.
HERMES_COMMIT="7de12dc2d1c009c5cc4c0e67b8c537ea9e370e99"
HERMES_PATCH="$SCRIPT_DIR/patches/evdi-fix.patch"

# ------------------------------------------------------------
# 0. Install manifest
# ------------------------------------------------------------
# Every change this script makes to the system is recorded here,
# so uninstall.sh can remove exactly that and nothing else.
# Anything that already existed before installation is NOT recorded.
#
# Format: <type><TAB><value>, one entry per line.

STATE_DIR="$HOME/.local/state/screen-spawner"
MANIFEST="$STATE_DIR/installed.list"
BACKUP_DIR="$STATE_DIR/backup"

mkdir -p "$STATE_DIR"
touch "$MANIFEST"

# record <type> <value>
record() {
    local entry
    entry="$1"$'\t'"$2"
    grep -qxF "$entry" "$MANIFEST" || printf '%s\n' "$entry" >> "$MANIFEST"
}

# Save a copy of an existing system file before overwriting it,
# so uninstall.sh can restore the original.
backup_file() {
    local src="$1"
    local dst="$BACKUP_DIR$1"

    # Created by this script on a previous run: nothing to restore
    grep -qxF "rootfile"$'\t'"$src" "$MANIFEST" && return 0

    if [ ! -e "$dst" ]; then
        mkdir -p "$(dirname "$dst")"
        cp -p "$src" "$dst"
    fi

    record restore "$src"
}

installed_packages() {
    dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' 2>/dev/null \
        | awk '$1 ~ /^ii/ { print $2 }' \
        | sort
}

# Install apt packages and record every package that was not
# installed before, including automatically pulled dependencies.
#
# A new package is NOT recorded if a package that was already installed
# now depends on it. Example: the toolchain PPA upgrades libgcc-s1 and
# libstdc++6, which then require the new gcc-16-base. Removing it later
# would break the whole system, including apt itself.
#
# The rule is transitive: a new package that a kept new package depends
# on is kept too. Example on Debian: e2fsprogs is kept, so its new
# dependency libss2 must be kept as well, or uninstall cannot remove it.
apt_install() {
    local before after new keep pkg status=0

    before="$(installed_packages)"
    sudo apt install -y "$@" || status=$?
    after="$(installed_packages)"
    new="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sed '/^$/d')"
    [ -n "$new" ] || return "$status"

    # One rdepends call for all new packages; only real dependencies
    # count, not Breaks/Replaces/Recommends. awk then keeps every new
    # package that something staying installed depends on, repeating
    # until nothing more is added.
    # shellcheck disable=SC2046  # one package name per word
    keep="$(
        {
            # Packages recorded by an earlier apt_install call go away
            # on uninstall, so they do not count as staying installed.
            awk -F'\t' '$1 == "apt" { sub(/:.*/, "", $2); print "rec " $2 }' "$MANIFEST" 2>/dev/null
            printf '%s\n' "$before" | sed '/^$/d; s/:.*//; s/^/old /'
            printf '%s\n' "$new" | sed 's/:.*//; s/^/new /'
            apt-cache rdepends --installed \
                --no-recommends --no-suggests --no-conflicts \
                --no-breaks --no-replaces --no-enhances \
                $(printf '%s\n' "$new") 2>/dev/null
        } | awk '
            $1 == "rec" && NF == 2 { rec[$2] = 1; next }
            $1 == "old" && NF == 2 { if (!($2 in rec)) stays[$2] = 1; next }
            $1 == "new" && NF == 2 { isnew[$2] = 1; next }
            /^Reverse Depends:/ { next }
            /^[^ ]/ { pkg = $1; next }
            pkg != "" { d = $0; sub(/^[ |]*/, "", d); sub(/:.*/, "", d); users[pkg] = users[pkg] " " d }
            END {
                do {
                    changed = 0
                    for (p in isnew) {
                        if (p in kept) continue
                        n = split(users[p], u, " ")
                        for (i = 1; i <= n; i++)
                            if (u[i] in stays) { stays[p] = kept[p] = 1; print p; changed = 1; break }
                    }
                } while (changed)
            }'
    )"

    while read -r pkg; do
        if printf '%s\n' "$keep" | grep -qxF "${pkg%%:*}"; then
            echo "Not recorded (required by packages that stay installed): $pkg"
            continue
        fi
        record apt "$pkg"
    done <<< "$new"
    return "$status"
}

# Print the first package name that exists in the apt repositories.
# EVDI package names differ between Ubuntu releases
# (22.04: libevdi0 / libevdi0-dev, newer: libevdi1 / libevdi-dev).
first_available() {
    local pkg
    for pkg in "$@"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            echo "$pkg"
            return 0
        fi
    done

    echo "ERROR: none of these packages is available: $*" >&2
    return 1
}

# Which package manager this system has: Debian and Ubuntu (apt), Fedora (dnf)
# or Arch Linux (pacman). Each has its own branch below where they differ.
DISTRO=debian
OS_ID=
OS_LIKE=
OS_VERSION=
if [ -r /etc/os-release ]; then
    OS_ID="$(. /etc/os-release; echo "${ID:-}")"
    OS_LIKE="$(. /etc/os-release; echo "${ID_LIKE:-}")"
    OS_VERSION="$(. /etc/os-release; echo "${VERSION_ID:-}")"
fi
case " $OS_ID $OS_LIKE " in
    *" fedora "*) DISTRO=fedora ;;
    *" arch "*) DISTRO=arch ;;
esac
if [ "$DISTRO" != debian ] && [ "$BUILD_FROM_SOURCE" -eq 1 ]; then
    echo "ERROR: --build-from-source is available on Debian and Ubuntu only." >&2
    exit 2
fi

# Fedora and Arch: install packages by name (or an .rpm / .pkg.tar.zst file) and
# record those that were not installed before. Only the packages asked for are
# recorded; dnf and pacman mark what they pull in as dependencies and remove it
# with them again, if nothing else needs it.
pkg_name_of() {
    case "$1" in
        *.rpm) rpm -qp --qf '%{NAME}\n' "$1" 2>/dev/null ;;
        *.pkg.tar.*) pacman -Qp "$1" 2>/dev/null | awk '{print $1}' ;;
        *) printf '%s\n' "$1" ;;
    esac
}

pkg_installed() {
    case "$DISTRO" in
        fedora) rpm -q "$1" >/dev/null 2>&1 ;;
        arch) pacman -Q "$1" >/dev/null 2>&1 ;;
        *) dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii' ;;
    esac
}

sys_install() {
    local arg name status=0 wanted=()
    for arg in "$@"; do
        name="$(pkg_name_of "$arg")"
        pkg_installed "$name" || wanted+=("$name")
    done
    case "$DISTRO" in
        # Without weak dependencies: dnf does not take those away on removal.
        fedora) sudo dnf install -y --setopt=install_weak_deps=False "$@" || status=$? ;;
        arch)
            if ! sudo pacman -S --needed --noconfirm "$@"; then
                status=1
                echo "If pacman could not download a package, upgrade the system first"
                echo "(sudo pacman -Syu), restart if the kernel was updated, and run install.sh again."
            fi ;;
    esac
    for name in "${wanted[@]}"; do
        pkg_installed "$name" && record "$DISTRO_PM" "$name"
    done
    return "$status"
}

sys_install_file() {
    local name status=0
    name="$(pkg_name_of "$1")"
    [ -n "$name" ] || return 1
    local was=0
    pkg_installed "$name" && was=1
    case "$DISTRO" in
        fedora) sudo dnf install -y --setopt=install_weak_deps=False "$1" || status=$? ;;
        arch) sudo pacman -U --noconfirm "$1" || status=$? ;;
    esac
    if [ "$was" -eq 0 ] && pkg_installed "$name"; then
        record "$DISTRO_PM" "$name"
    fi
    return "$status"
}

case "$DISTRO" in
    fedora) DISTRO_PM=dnf ;;
    arch) DISTRO_PM=pacman ;;
    *) DISTRO_PM=apt ;;
esac

echo "Install manifest: $MANIFEST"

# Refresh package lists once; repeated only after adding a repository
echo
echo "=== Updating package lists ==="

case "$DISTRO" in
    debian) sudo apt update ;;
    fedora) sudo dnf makecache ;;
    arch)
        # Refreshing the lists without upgrading (pacman -Sy) would make a
        # partial upgrade, which Arch does not support. The lists of the last
        # full upgrade are used; if they are too old, installing fails and says so.
        echo "Using the package lists of the last system upgrade (pacman -Syu)." ;;
esac

# ------------------------------------------------------------
# 1. Install EVDI
# ------------------------------------------------------------

echo
echo "=== Checking EVDI ==="

# Kernel headers must be installed BEFORE evdi-dkms:
# DKMS builds the kernel module while the package is being installed.
#
# They are intentionally NOT recorded in the manifest:
# other DKMS modules may depend on them.
case "$DISTRO" in
debian)
    if ! dpkg -s "linux-headers-$(uname -r)" >/dev/null 2>&1; then
        sudo apt install -y "linux-headers-$(uname -r)"
    fi

    EVDI_LIB="$(first_available libevdi1 libevdi0)"
    EVDI_DEV="$(first_available libevdi-dev libevdi0-dev)"

    if ! dpkg -s evdi-dkms >/dev/null 2>&1 || \
       ! dpkg -s "$EVDI_LIB" >/dev/null 2>&1 || \
       ! dpkg -s "$EVDI_DEV" >/dev/null 2>&1; then

        apt_install evdi-dkms "$EVDI_LIB" "$EVDI_DEV"
    fi ;;
fedora)
    if ! rpm -q "kernel-devel-$(uname -r)" >/dev/null 2>&1; then
        if ! sudo dnf install -y "kernel-devel-$(uname -r)"; then
            echo "ERROR: the headers of the running kernel ($(uname -r)) are not available." >&2
            echo "Update the system (sudo dnf upgrade), restart, and run install.sh again." >&2
            exit 1
        fi
    fi
    # Fedora has no EVDI package; the negativo17 repository has one, built for
    # each Fedora release. Only the EVDI packages are taken from it, so it
    # never replaces anything else on the system.
    EVDI_REPO=/etc/yum.repos.d/screen-spawner-evdi.repo
    if [ ! -e "$EVDI_REPO" ]; then
        record rootfile "$EVDI_REPO"
        sudo tee "$EVDI_REPO" >/dev/null <<'REPO'
[screen-spawner-evdi]
name=EVDI from negativo17 Multimedia, for Screen Spawner
baseurl=https://negativo17.org/repos/multimedia/fedora-$releasever/$basearch/
enabled=1
gpgcheck=1
gpgkey=https://negativo17.org/repos/RPM-GPG-KEY-slaanesh
includepkgs=dkms-evdi,libevdi
REPO
    fi
    keys_before="$(rpm -q gpg-pubkey 2>/dev/null | sort)"
    if ! pkg_installed dkms-evdi || ! pkg_installed libevdi; then
        sys_install dkms-evdi libevdi
    fi
    # The repository's signing key, imported by dnf on first use.
    while read -r key; do
        [ -n "$key" ] && record rpmkey "$key"
    done < <(comm -13 <(printf '%s\n' "$keys_before") <(rpm -q gpg-pubkey 2>/dev/null | sort))
    pkg_installed dkms-evdi || { echo "ERROR: EVDI could not be installed." >&2; exit 1; } ;;
arch)
    # The headers package belongs to the running kernel's package: linux,
    # linux-lts, linux-zen...
    kernel_pkg="$(pacman -Qqo "/usr/lib/modules/$(uname -r)" 2>/dev/null | head -n 1)"
    headers_pkg="${kernel_pkg:-linux}-headers"
    if ! pacman -Q "$headers_pkg" >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm "$headers_pkg"
    fi
    # EVDI is in the AUR only: build its package here, as an AUR helper would.
    if ! pacman -Q evdi-dkms >/dev/null 2>&1; then
        sys_install base-devel git dkms
        aur_dir="$(mktemp -d)"
        git clone --depth 1 https://aur.archlinux.org/evdi-dkms.git "$aur_dir/evdi-dkms"
        # makepkg may also make a -debug package; only the module package is installed.
        if (cd "$aur_dir/evdi-dkms" && makepkg --syncdeps --rmdeps --noconfirm); then
            evdi_pkg="$(ls "$aur_dir"/evdi-dkms/evdi-dkms-[0-9]*.pkg.tar.* 2>/dev/null | head -n 1)"
            [ -n "$evdi_pkg" ] && sys_install_file "$evdi_pkg"
        fi
        rm -rf "$aur_dir"
        pacman -Q evdi-dkms >/dev/null 2>&1 || { echo "ERROR: EVDI could not be built from the AUR." >&2; exit 1; }
    fi ;;
esac

# EVDI creates its devices when it loads, one per device that can connect
# at once: Hermes uses an existing device without root access to
# /sys/devices/evdi/add, and adding one later, with the desktop running,
# makes X11 take it for a new graphics card. An unused device costs nothing.
# 1 was the number before Screen Spawner 0.3.0; any other number was chosen
# in the app (Devices at once) and stays.
EVDI_MODPROBE_CONFIG="/etc/modprobe.d/evdi.conf"
EVDI_DEVICES=4
EVDI_RESTART_NOTE=0
evdi_devices_now=$(sed -n 's/^options evdi initial_device_count=\([0-9]\+\)$/\1/p' \
    "$EVDI_MODPROBE_CONFIG" 2>/dev/null | tail -n 1)

if [ -z "$evdi_devices_now" ] || [ "$evdi_devices_now" = 1 ]; then
    echo "Configuring EVDI for $EVDI_DEVICES devices at once..."

    if [ -f "$EVDI_MODPROBE_CONFIG" ]; then
        backup_file "$EVDI_MODPROBE_CONFIG"
    else
        record rootfile "$EVDI_MODPROBE_CONFIG"
    fi

    echo "options evdi initial_device_count=$EVDI_DEVICES" | sudo tee "$EVDI_MODPROBE_CONFIG" >/dev/null
else
    EVDI_DEVICES=$evdi_devices_now
fi
# Loaded earlier with fewer devices: the new number applies from the next start.
if lsmod | grep -q '^evdi' && \
   [ "$(cat /sys/devices/evdi/count 2>/dev/null || echo 0)" -lt "$EVDI_DEVICES" ]; then
    EVDI_RESTART_NOTE=1
fi

if ! lsmod | grep -q '^evdi'; then
    sudo modprobe evdi
    record module evdi
fi

# evdi-dkms does not load the module at boot. Without this, Hermes
# would lose its virtual display after the first reboot.
if ! grep -qsxF evdi /etc/modules /etc/modules-load.d/*.conf; then
    echo "Enabling EVDI at boot..."
    if [ "$DISTRO" = debian ]; then
        record line "/etc/modules"$'\t'"evdi"
        echo evdi | sudo tee -a /etc/modules >/dev/null
    else
        if [ ! -d /etc/modules-load.d ]; then
            record rootdir /etc/modules-load.d
            sudo mkdir -p /etc/modules-load.d
        fi
        record rootfile /etc/modules-load.d/screen-spawner-evdi.conf
        echo evdi | sudo tee /etc/modules-load.d/screen-spawner-evdi.conf >/dev/null
    fi
fi

# The login screen waits for the real graphics card, not for EVDI's virtual
# ones; and a start that did not reach the login screen is followed by one
# without EVDI (app/system/). The packages install the same files under /usr/lib.
install_root_file() {   # install_root_file MODE SOURCE DEST
    [ -e "$3" ] || [ -L "$3" ] || record rootfile "$3"
    sudo install -D -m "$1" "$2" "$3"
}
link_root_file() {      # link_root_file TARGET LINK
    if [ ! -d "$(dirname "$2")" ]; then
        record rootdir "$(dirname "$2")"
        sudo mkdir -p "$(dirname "$2")"
    fi
    [ -e "$2" ] || [ -L "$2" ] || record rootfile "$2"
    sudo ln -sfn "$1" "$2"
}
echo "Setting up the safe start..."
SAFE_DIR=/usr/local/lib/screen-spawner
[ -d "$SAFE_DIR" ] || record rootdir "$SAFE_DIR"
[ -d /var/lib/screen-spawner ] || record rootdir /var/lib/screen-spawner
record rootfile /var/lib/screen-spawner/boot-pending
install_root_file 644 "$SCRIPT_DIR/app/system/72-screen-spawner-evdi.rules" /etc/udev/rules.d/72-screen-spawner-evdi.rules
install_root_file 755 "$SCRIPT_DIR/app/system/screen-spawner-boot-guard" "$SAFE_DIR/screen-spawner-boot-guard"
# In /usr/local/lib/systemd/system, enabled by their links there: systemd
# reads it like /usr/lib, and resetting the presets in /etc does not undo it.
UNIT_DIR=/usr/local/lib/systemd/system
for d in /usr/local/lib/systemd "$UNIT_DIR"; do
    [ -d "$d" ] || record rootdir "$d"
done
for unit in screen-spawner-safe-start.service screen-spawner-start-ok.service; do
    tmp_unit="$(mktemp)"
    sed "s|/usr/lib/screen-spawner/|$SAFE_DIR/|" "$SCRIPT_DIR/app/system/$unit" > "$tmp_unit"
    install_root_file 644 "$tmp_unit" "$UNIT_DIR/$unit"
    rm -f "$tmp_unit"
done
link_root_file ../screen-spawner-safe-start.service "$UNIT_DIR/sysinit.target.wants/screen-spawner-safe-start.service"
link_root_file ../screen-spawner-start-ok.service "$UNIT_DIR/graphical.target.wants/screen-spawner-start-ok.service"
if [ -d /run/systemd/system ]; then
    sudo systemctl daemon-reload || true
    sudo udevadm control --reload || true
    sudo udevadm trigger --subsystem-match=drm --action=change || true
fi

# Release package checksums are pinned here, never fetched alongside the package.
select_package() {
    local ID= VERSION_ID= ID_LIKE= UBUNTU_CODENAME= VERSION_CODENAME=
    [ -r /etc/os-release ] || return 1
    . /etc/os-release
    PACKAGE_RELEASE=v0.2.2
    case "$DISTRO" in
    fedora)
        [ "$(uname -m)" = x86_64 ] || return 1
        case "$VERSION_ID" in
            45) PACKAGE_SYSTEM=fedora45
                PACKAGE_SHA256="269665a8c3eb7e6b3c83687e1db0081f4de32f3ced70decab1ef0d0fff4bb85b" ;;
            *) return 1 ;;
        esac
        PACKAGE_RELEASE=v0.2.2
        PACKAGE_FILE="hermes-screen-spawner-0.5.1-ss0.2.2.fc45.x86_64.rpm"
        return 0 ;;
    arch)
        [ "$(uname -m)" = x86_64 ] || return 1
        PACKAGE_SYSTEM=arch
        PACKAGE_SHA256="86c5782dec69bf86c4d65c5bf40e2f1cd221f7f52e06d33bf768239e2835fb41"
        PACKAGE_RELEASE=v0.2.2
        PACKAGE_FILE="hermes-screen-spawner-0.5.1.ss0.2.2-1-x86_64.pkg.tar.zst"
        return 0 ;;
    esac
    [ "$(dpkg --print-architecture)" = amd64 ] || return 1
    PACKAGE_SYSTEM=
    case "$ID:$VERSION_ID" in
        ubuntu:22.04) PACKAGE_SYSTEM=ubuntu22.04 ;;
        ubuntu:24.04) PACKAGE_SYSTEM=ubuntu24.04 ;;
        ubuntu:26.04) PACKAGE_SYSTEM=ubuntu26.04 ;;
        debian:13|debian:13.*) PACKAGE_SYSTEM=debian13 ;;
        linuxmint:22|linuxmint:22.*)
            [ "$UBUNTU_CODENAME" = noble ] || return 1
            PACKAGE_SYSTEM=ubuntu24.04 ;;
        *)
            case " $ID_LIKE " in
                *" ubuntu "*)
                    case "$UBUNTU_CODENAME" in
                        jammy) PACKAGE_SYSTEM=ubuntu22.04 ;;
                        noble) PACKAGE_SYSTEM=ubuntu24.04 ;;
                        resolute) PACKAGE_SYSTEM=ubuntu26.04 ;;
                    esac ;;
            esac ;;
    esac
    case "$PACKAGE_SYSTEM" in
        ubuntu22.04) PACKAGE_SHA256="db229899a6f0c3352dec39e109faae7c718dbdd5567f3a1671ae2b29577f007c" ;;
        ubuntu24.04) PACKAGE_SHA256="1d9dbe150bac0d7b0105f2def2420a8c69327e54504c39e1b764774d3945d3af" ;;
        ubuntu26.04) PACKAGE_SHA256="13365ba7a5d4b07acecba417f3412a551f2adf7205fefdd2cad39cb07bdac268" ;;
        debian13) PACKAGE_SHA256="eea27360ea1101d2fcf0d41d487973d03d4513f016178c966622fa8008a9d236" ;;
        *) return 1 ;;
    esac
    PACKAGE_FILE="hermes-screen-spawner_0.5.1+ss0.2.2_${PACKAGE_SYSTEM}_amd64.deb"
}

confirm_source_build() {
    local answer
    echo
    echo "A verified prebuilt Hermes package could not be installed."
    echo "Building Hermes from source may take about an hour."
    while true; do
        if ! read -r -p "Continue with the source build? [Y/n]: " answer; then
            echo
            echo "Installation stopped before building Hermes."
            return 1
        fi
        case "$answer" in
            ""|[yY]|[yY][eE][sS]) return 0 ;;
            [nN]|[nN][oO])
                echo "Installation stopped before building Hermes."
                return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

install_release_package() {
    local download_dir package_path status=0
    if ! select_package; then
        [ "$DISTRO" = debian ] || echo "ERROR: there is no Hermes package for this system ($OS_ID $OS_VERSION)." >&2
        return 1
    fi
    if pkg_installed hermes || pkg_installed Hermes; then
        echo "WARNING: the official Hermes package is installed; leaving it in place."
        return 1
    fi
    echo
    echo "=== Installing the Hermes release package ($PACKAGE_SYSTEM) ==="
    download_dir="$(mktemp -d)" || return 1
    chmod 755 "$download_dir"
    package_path="$download_dir/$PACKAGE_FILE"
    if [ -n "${SCREEN_SPAWNER_PACKAGE_DIR:-}" ]; then
        cp -- "$SCREEN_SPAWNER_PACKAGE_DIR/$PACKAGE_FILE" "$package_path" || status=$?
    else
        if ! command -v curl >/dev/null 2>&1; then
            if [ "$DISTRO" = debian ]; then
                apt_install curl ca-certificates || status=$?
            else
                sys_install curl || status=$?
            fi
        fi
        if [ "$status" -eq 0 ]; then
            curl --fail --location --retry 3 --connect-timeout 20 \
                --max-time 600 --output "$package_path" \
                "https://github.com/itkawa/screen-spawner-packages/releases/download/$PACKAGE_RELEASE/$PACKAGE_FILE" || status=$?
        fi
    fi
    if [ "$status" -eq 0 ]; then
        chmod 644 "$package_path" || status=$?
    fi
    if [ "$status" -eq 0 ]; then
        printf '%s  %s\n' "$PACKAGE_SHA256" "$package_path" | sha256sum --check --status || status=$?
    fi
    if [ "$status" -eq 0 ]; then
        chmod 644 "$package_path"
        if [ "$DISTRO" = debian ]; then
            apt_install "$package_path" || status=$?
        else
            sys_install_file "$package_path" || status=$?
        fi
    fi
    rm -rf -- "$download_dir"
    [ "$status" -eq 0 ] || return 1
    HERMES_COMMAND=/usr/bin/sunshine
    HERMES_WORKDIR="$HOME"
    return 0
}

HERMES_COMMAND="$PROJECT_DIR/build/sunshine"
HERMES_WORKDIR="$PROJECT_DIR"
PACKAGE_INSTALLED=0
if [ "$BUILD_FROM_SOURCE" -eq 0 ]; then
    if install_release_package; then
        PACKAGE_INSTALLED=1
    elif [ "$DISTRO" != debian ]; then
        # The source build below uses apt; on Fedora and Arch it is not offered.
        echo "ERROR: the Hermes package could not be installed." >&2
        exit 1
    else
        confirm_source_build || exit 0
        echo "=== Building Hermes from source ==="
    fi
fi

if [ "$PACKAGE_INSTALLED" -eq 0 ]; then
# ------------------------------------------------------------
# 2. Clone or reuse Apollo-Linux
# ------------------------------------------------------------

echo
echo "=== Checking Apollo-Linux ==="

if [ ! -d "$PROJECT_DIR/.git" ]; then

    if [ -e "$PROJECT_DIR" ]; then
        echo "ERROR: $PROJECT_DIR exists but is not a Git repository."
        echo "Please move or remove it manually before running this script."
        exit 1
    fi

    git clone https://github.com/MrOz59/Hermes "$PROJECT_DIR"
    record dir "$PROJECT_DIR"
fi

cd "$PROJECT_DIR"

# Use the verified revision, without overwriting local changes
if [ "$(git rev-parse HEAD)" != "$HERMES_COMMIT" ]; then
    if ! git diff --quiet HEAD --; then
        echo "ERROR: $PROJECT_DIR has uncommitted changes and is not at the"
        echo "verified commit $HERMES_COMMIT."
        echo "Please commit or remove those changes and run this script again."
        exit 1
    fi
    git fetch origin
    git checkout --detach "$HERMES_COMMIT"
fi

# Apply the EVDI fix unless a previous run already did
if git apply --reverse --check "$HERMES_PATCH" 2>/dev/null; then
    echo "EVDI fix is already applied."
else
    git apply "$HERMES_PATCH"
    echo "EVDI fix applied."
fi

# Initialize and update submodules
git submodule update --init --recursive

# ------------------------------------------------------------
# 3. Install build dependencies
# ------------------------------------------------------------

echo
echo "=== Installing build dependencies ==="

apt_install \
    build-essential \
    python3 \
    pkg-config \
    git \
    wget \
    curl \
    libssl-dev \
    libcurl4-openssl-dev \
    libminiupnpc-dev \
    libdrm-dev \
    libevdev-dev \
    libcap-dev \
    libva-dev \
    libva-drm2 \
    libx11-dev \
    libopus-dev \
    libxfixes-dev \
    libxrandr-dev \
    libxcb-shm0-dev \
    libxcb-xfixes0-dev \
    libpulse-dev \
    libsystemd-dev \
    libnuma-dev \
    libgbm-dev \
    qtbase5-dev \
    libqt5svg5-dev \
    ninja-build

# ------------------------------------------------------------
# 4. Choose the compiler: the system GCC if it is 13 or newer, else GCC 13
# ------------------------------------------------------------

echo
echo "=== Checking GCC ==="

# Hermes needs GCC 13 or newer. Where the system compiler is new enough
# (Ubuntu 24.04+), use it: system libraries such as Qt are built with it, and
# linking them with an older GCC fails on a newer libstdc++ ABI.
SYSTEM_GCC_MAJOR="$(gcc -dumpversion 2>/dev/null | cut -d. -f1)"

if [ "${SYSTEM_GCC_MAJOR:-0}" -ge 13 ] 2>/dev/null && command -v g++ >/dev/null 2>&1; then
    echo "Using the system GCC $SYSTEM_GCC_MAJOR."
    BUILD_CC=/usr/bin/gcc
    BUILD_CXX=/usr/bin/g++
else
    if ! command -v gcc-13 >/dev/null 2>&1 || \
       ! command -v g++-13 >/dev/null 2>&1; then

        # The toolchain PPA is added only when gcc-13 is not available in the
        # standard repositories. Besides gcc-13 the PPA also upgrades system
        # libraries such as libstdc++6 and libgcc-s1.
        if ! first_available gcc-13 >/dev/null 2>&1 && \
           ! grep -qs "ubuntu-toolchain-r/test" \
            /etc/apt/sources.list \
            /etc/apt/sources.list.d/*.list \
            /etc/apt/sources.list.d/*.sources; then

            sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
            record ppa ubuntu-toolchain-r/test
            sudo apt update
        fi

        apt_install gcc-13 g++-13
    fi
    echo "Using GCC 13 (the system GCC is ${SYSTEM_GCC_MAJOR:-unknown})."
    BUILD_CC=/usr/bin/gcc-13
    BUILD_CXX=/usr/bin/g++-13
fi

# ------------------------------------------------------------
# 5. Install CMake if needed
# ------------------------------------------------------------

echo
echo "=== Checking CMake ==="

# Hermes needs CMake 3.24 or newer. Take it from apt where apt has one that
# new (Ubuntu 24.04+, Debian 13, Linux Mint 22); otherwise from snap, which
# Linux Mint blocks and Debian does not ship by default.
if ! command -v cmake >/dev/null 2>&1; then
    APT_CMAKE="$(apt-cache policy cmake 2>/dev/null | awk '/Candidate:/ {print $2}')"
    if [ -n "$APT_CMAKE" ] && [ "$APT_CMAKE" != "(none)" ] && \
       dpkg --compare-versions "$APT_CMAKE" ge 3.24; then
        apt_install cmake
    else
        sudo snap install cmake --classic
        record snap cmake
    fi
fi

# ------------------------------------------------------------
# 6. Install / load NVM
# ------------------------------------------------------------

echo
echo "=== Checking NVM ==="

export NVM_DIR="$HOME/.nvm"

if [ ! -s "$NVM_DIR/nvm.sh" ]; then

    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    record nvm "$NVM_DIR"
fi

source "$NVM_DIR/nvm.sh"

# ------------------------------------------------------------
# 7. Install Node.js 22 if needed
# ------------------------------------------------------------

echo
echo "=== Checking Node.js 22 ==="

if ! nvm ls 22 | grep -q "v22"; then
    nvm install 22
    record node 22
fi

nvm use 22

# The Hermes web UI build fills the npm cache (about 200 MB).
# It is only a cache, so uninstall.sh may remove it even if
# npm was used for something else later.
[ -e "$HOME/.npm" ] || record dir "$HOME/.npm"

# ------------------------------------------------------------
# 10. Configure CMake
# ------------------------------------------------------------

echo
echo "=== Configuring Apollo-Linux ==="

cd "$PROJECT_DIR"

# CMake drops a cache built with another compiler and then forgets the options
# below, so start that configuration over (after an earlier run with GCC 13).
if [ -f build/CMakeCache.txt ] && \
   ! grep -qxF -e "CMAKE_CXX_COMPILER:STRING=$BUILD_CXX" \
               -e "CMAKE_CXX_COMPILER:FILEPATH=$BUILD_CXX" build/CMakeCache.txt; then
    echo "The compiler changed since the last build; reconfiguring from scratch."
    rm -rf build/CMakeCache.txt build/CMakeFiles
fi

cmake -B build -G Ninja -S . \
    -DSUNSHINE_ENABLE_CUDA=OFF \
    -DCUDA_FAIL_ON_MISSING=OFF \
    -DCMAKE_C_COMPILER="$BUILD_CC" \
    -DCMAKE_CXX_COMPILER="$BUILD_CXX"

# ------------------------------------------------------------
# 11. Build Hermes
# ------------------------------------------------------------

echo
echo "=== Building Hermes ==="

cd "$PROJECT_DIR"

# Single job by default: parallel C++ compilation of Hermes can run out
# of memory on laptops. Faster build: BUILD_JOBS=4 ./install.sh
ninja -C build -j"${BUILD_JOBS:-1}"

# ------------------------------------------------------------
# 12. Install runtime assets
# ------------------------------------------------------------

echo
echo "=== Installing runtime assets ==="

ASSETS_SRC="$PROJECT_DIR/build/assets"
ASSETS_DST="/usr/local/assets"

python3 "$SCRIPT_DIR/packaging/add-source-notice.py" "$ASSETS_SRC/web"

if [ -d "$ASSETS_SRC" ]; then

    # Record only directories and files that do not exist yet.
    # find lists parents before children, so uninstall.sh (which goes
    # in reverse order) removes files first and then empty directories.
    [ -d "$ASSETS_DST" ] || record rootdir "$ASSETS_DST"

    while IFS= read -r -d '' item; do
        rel="${item#"$ASSETS_SRC"/}"
        dest="$ASSETS_DST/$rel"

        # Symlinks (e.g. shaders -> source tree) are copied as links,
        # so they are recorded as files, not directories
        if [ -d "$item" ] && [ ! -L "$item" ]; then
            [ -d "$dest" ] || record rootdir "$dest"
        else
            [ -e "$dest" ] || [ -L "$dest" ] || record rootfile "$dest"
        fi
    done < <(find "$ASSETS_SRC" -mindepth 1 -print0)

    sudo mkdir -p "$ASSETS_DST"
    sudo cp -r "$ASSETS_SRC/." "$ASSETS_DST/"
else
    echo "ERROR: build/assets directory was not found."
    exit 1
fi

fi # source build and runtime asset installation

# ------------------------------------------------------------
# 8. Install Intel VAAPI driver
# ------------------------------------------------------------

echo
echo "=== Checking Intel VAAPI ==="

case "$DISTRO" in
    debian)
        if ! dpkg -s intel-media-va-driver >/dev/null 2>&1; then
            apt_install intel-media-va-driver
        fi ;;
    fedora) pkg_installed libva-intel-media-driver || sys_install libva-intel-media-driver ;;
    arch) pkg_installed intel-media-driver || sys_install intel-media-driver ;;
esac

# ------------------------------------------------------------
# 9. Check VAAPI
# ------------------------------------------------------------

echo
echo "=== VAAPI check ==="

if command -v vainfo >/dev/null 2>&1; then
    vainfo || true
else
    echo "WARNING: vainfo is not installed."
    echo "Installing vainfo for verification..."
    if [ "$DISTRO" = debian ]; then
        apt_install vainfo
    else
        sys_install libva-utils
    fi
    vainfo || true
fi

# ------------------------------------------------------------
# 13. Verify Hermes binary
# ------------------------------------------------------------

echo
echo "=== Hermes version ==="

"$HERMES_COMMAND" --version

# ------------------------------------------------------------
# 14. Keep sound on the computer's own speakers
# ------------------------------------------------------------

# Without this Hermes switches the whole system's sound to the tablet
# while it is connected, and the laptop's speakers go silent.
HERMES_CONFIG="$HOME/.config/hermes/hermes.conf"
AUDIO_LINE="stream_audio = false"

if ! grep -qsE '^[[:space:]]*stream_audio[[:space:]]*=' "$HERMES_CONFIG"; then
    echo
    echo "=== Keeping sound on the computer's speakers ==="
    mkdir -p "$(dirname "$HERMES_CONFIG")"
    record line "$HERMES_CONFIG"$'\t'"$AUDIO_LINE"
    # Hermes may have written the file without a final newline
    if [ -s "$HERMES_CONFIG" ] && [ -n "$(tail -c1 "$HERMES_CONFIG")" ]; then
        echo >> "$HERMES_CONFIG"
    fi
    echo "$AUDIO_LINE" >> "$HERMES_CONFIG"
fi

# ------------------------------------------------------------
# 15. Create / update desktop launcher
# ------------------------------------------------------------

echo
echo "=== Creating Hermes launcher ==="

mkdir -p "$HOME/.local/share/applications"

[ -e "$LAUNCHER" ] || record file "$LAUNCHER"

# The Screen Spawner app reads the Hermes command from this launcher too.
cat > "$LAUNCHER" <<EOF
[Desktop Entry]
Name=Hermes
Comment=Game streaming server
Exec="$HERMES_COMMAND"
Path=$HERMES_WORKDIR
Terminal=true
Type=Application
Categories=Network;
EOF

chmod +x "$LAUNCHER"

# ------------------------------------------------------------
# 15a. Install the Screen Spawner app
# ------------------------------------------------------------
# A window and a top bar icon to start Hermes, pair devices, switch between
# extended and mirrored, and see the load. It goes to the user's own folders,
# with a launcher in the application menu.

echo
echo "=== Installing the Screen Spawner app ==="

APP_DATA="$HOME/.local/share/screen-spawner"
APP_LAUNCHER="$HOME/.local/share/applications/screen-spawner.desktop"
ICON_ROOT="$HOME/.local/share/icons/hicolor"

# Python with GTK 3 and the top bar icon library. Usually already there on a
# GNOME desktop; apt_install records only what it adds.
APPINDICATOR_NOTE=0
if [ "$DISTRO" != debian ]; then
    if [ "$DISTRO" = fedora ]; then
        APP_PACKAGES=(python3-gobject gobject-introspection gtk3 libayatana-appindicator-gtk3 polkit)
    else
        APP_PACKAGES=(python-gobject gtk3 libayatana-appindicator polkit)
    fi
    if command -v gnome-shell >/dev/null 2>&1 && ! pkg_installed gnome-shell-extension-appindicator; then
        APP_PACKAGES+=(gnome-shell-extension-appindicator)
    fi
    MISSING_PACKAGES=()
    for pkg in "${APP_PACKAGES[@]}"; do
        pkg_installed "$pkg" || MISSING_PACKAGES+=("$pkg")
    done
    if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
        sys_install "${MISSING_PACKAGES[@]}"
    fi
    if [[ " ${MISSING_PACKAGES[*]} " == *" gnome-shell-extension-appindicator "* ]]; then
        gnome-extensions enable appindicatorsupport@rgcjonas.gmail.com 2>/dev/null || true
        APPINDICATOR_NOTE=1
    fi
else
APP_PACKAGES=(python3-gi gir1.2-gtk-3.0)
INDICATOR_PKG="$(first_available gir1.2-ayatanaappindicator3-0.1 || true)"
[ -n "$INDICATOR_PKG" ] && APP_PACKAGES+=("$INDICATOR_PKG")
# Ubuntu ships its own AppIndicator extension for GNOME Shell; plain GNOME,
# as on Debian, needs one to show the top bar icon.
if command -v gnome-shell >/dev/null 2>&1 &&
   ! dpkg -s gnome-shell-extension-appindicator >/dev/null 2>&1 &&
   ! dpkg -s gnome-shell-extension-ubuntu-appindicators >/dev/null 2>&1 &&
   apt-cache show gnome-shell-extension-appindicator >/dev/null 2>&1; then
    APP_PACKAGES+=(gnome-shell-extension-appindicator)
fi
MISSING_PACKAGES=()
for pkg in "${APP_PACKAGES[@]}"; do
    dpkg -s "$pkg" >/dev/null 2>&1 || MISSING_PACKAGES+=("$pkg")
done
if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    apt_install "${MISSING_PACKAGES[@]}"
fi
if [[ " ${MISSING_PACKAGES[*]} " == *" gnome-shell-extension-appindicator "* ]]; then
    # GNOME Shell sees a newly installed extension only after logging in again.
    gnome-extensions enable appindicatorsupport@rgcjonas.gmail.com 2>/dev/null || true
    APPINDICATOR_NOTE=1
fi
fi

# The app, its icons, and a copy of the uninstaller with the patch it needs,
# for the app's Uninstall button.
[ -e "$APP_DATA" ] || record dir "$APP_DATA"
mkdir -p "$APP_DATA/app" "$APP_DATA/patches"
cp -r "$SCRIPT_DIR/app/." "$APP_DATA/app/"
rm -rf "$APP_DATA/app/__pycache__"
chmod +x "$APP_DATA/app/screen-spawner"
cp "$SCRIPT_DIR/uninstall.sh" "$APP_DATA/uninstall.sh"
cp "$HERMES_PATCH" "$APP_DATA/patches/"
# The README, with the pictures it links to, for reading after installation.
mkdir -p "$APP_DATA/docs"
cp "$SCRIPT_DIR/README.md" "$APP_DATA/README.md"
cp "$SCRIPT_DIR"/docs/* "$APP_DATA/docs/"

# Icons in the standard place, so the menu and the window find them by name.
while IFS= read -r -d '' icon; do
    dest="$ICON_ROOT/${icon#"$SCRIPT_DIR/app/icons/hicolor/"}"
    [ -e "$dest" ] || record file "$dest"
    mkdir -p "$(dirname "$dest")"
    cp "$icon" "$dest"
done < <(find "$SCRIPT_DIR/app/icons/hicolor" -type f -print0)

[ -e "$APP_LAUNCHER" ] || record file "$APP_LAUNCHER"
cat > "$APP_LAUNCHER" <<EOF
[Desktop Entry]
Type=Application
Name=Screen Spawner
Comment=Use a tablet or phone as a second monitor
Keywords=tablet;phone;monitor;display;second;screen;moonlight;hermes;
Exec=$APP_DATA/app/screen-spawner
Icon=screen-spawner
Terminal=false
Categories=Utility;
StartupNotify=true
EOF
chmod +x "$APP_LAUNCHER"
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

# ------------------------------------------------------------
# 16. Final checks
# ------------------------------------------------------------

echo
echo "=== Final checks ==="

echo
echo "--- EVDI ---"
if lsmod | grep -q '^evdi'; then
    echo "EVDI kernel module: loaded"
else
    echo "WARNING: EVDI kernel module is not loaded"
fi

echo
echo "--- Hermes binary ---"
# build/sunshine is a symlink to a versioned binary (e.g. sunshine-0.5.1);
# the version is not hardcoded, so updates of Apollo-Linux do not break this
ls -lh "$HERMES_COMMAND"

HERMES_BINARY="$(readlink -f "$HERMES_COMMAND")"
if [ "$HERMES_BINARY" != "$HERMES_COMMAND" ]; then
    ls -lh "$HERMES_BINARY"
fi

echo
echo "--- Launcher ---"
ls -lh "$LAUNCHER"

echo
echo "=== Installation completed successfully ==="

next_step_heading() {
    echo
    if [ -z "${NO_COLOR:-}" ] && {
        [ "${FORCE_COLOR:-0}" = 1 ] || { [ -t 1 ] && [ "${TERM:-dumb}" != dumb ]; }
    }; then
        printf '\033[32m%s\033[0m\n' "$1"
    else
        printf '%s\n' "$1"
    fi
}

if [ "$EVDI_RESTART_NOTE" = 1 ]; then
    next_step_heading "Restart the computer:"
    echo "EVDI makes room for $EVDI_DEVICES devices at once when the computer starts."
    echo "Until then, fewer devices can connect at the same time."
fi

next_step_heading "Start:"
echo "Open Screen Spawner from the application menu and press Start."
echo "Hermes runs while the app runs; Quit stops both."
if [ "$APPINDICATOR_NOTE" = 1 ]; then
    echo "For the app's icon in the top bar, log out and in again once, and turn on"
    echo "the AppIndicator extension in the Extensions app if it is off."
fi

next_step_heading "To connect a device:"
echo "Open Moonlight on your tablet or phone, add this computer and tap it for a PIN."
echo "In Screen Spawner press Pair a device and enter the PIN. Then choose Desktop in Moonlight."
echo "How to use the app:"
echo "https://github.com/itkawa/screen-spawner#usage"
echo "or $APP_DATA/README.md"

next_step_heading "To uninstall:"
printf 'bash %q\n' "$SCRIPT_DIR/uninstall.sh"
echo "Your Hermes settings and paired devices are preserved."

next_step_heading "Install manifest:"
printf '%s\n' "$MANIFEST"
