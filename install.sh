#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

set -e

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
apt_install() {
    local before after pkg

    before="$(installed_packages)"
    sudo apt install -y "$@"
    after="$(installed_packages)"

    while read -r pkg; do
        [ -z "$pkg" ] && continue

        # Only real dependencies count, not Breaks/Replaces/Recommends
        if apt-cache rdepends --installed \
                --no-recommends --no-suggests --no-conflicts \
                --no-breaks --no-replaces --no-enhances \
                "$pkg" 2>/dev/null \
            | tail -n +3 \
            | sed 's/^[ |]*//; s/:.*//' \
            | grep -qxFf <(printf '%s\n' "$before" | sed 's/:.*//'); then

            echo "Not recorded (required by previously installed packages): $pkg"
            continue
        fi

        record apt "$pkg"
    done < <(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))
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

echo "Install manifest: $MANIFEST"

# Refresh package lists once; repeated only after adding a repository
echo
echo "=== Updating package lists ==="

sudo apt update

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
if ! dpkg -s "linux-headers-$(uname -r)" >/dev/null 2>&1; then
    sudo apt install -y "linux-headers-$(uname -r)"
fi

EVDI_LIB="$(first_available libevdi1 libevdi0)"
EVDI_DEV="$(first_available libevdi-dev libevdi0-dev)"

if ! dpkg -s evdi-dkms >/dev/null 2>&1 || \
   ! dpkg -s "$EVDI_LIB" >/dev/null 2>&1 || \
   ! dpkg -s "$EVDI_DEV" >/dev/null 2>&1; then

    apt_install evdi-dkms "$EVDI_LIB" "$EVDI_DEV"
fi

# EVDI must provide at least one pre-created virtual DRM device.
# This allows Hermes to use an existing device without requiring
# root access to /sys/devices/evdi/add.
EVDI_MODPROBE_CONFIG="/etc/modprobe.d/evdi.conf"

if [ ! -f "$EVDI_MODPROBE_CONFIG" ] || \
   ! grep -qxF 'options evdi initial_device_count=1' "$EVDI_MODPROBE_CONFIG"; then

    echo "Configuring EVDI with one initial virtual display..."

    if [ -f "$EVDI_MODPROBE_CONFIG" ]; then
        backup_file "$EVDI_MODPROBE_CONFIG"
    else
        record rootfile "$EVDI_MODPROBE_CONFIG"
    fi

    echo 'options evdi initial_device_count=1' | sudo tee "$EVDI_MODPROBE_CONFIG" >/dev/null
fi

if ! lsmod | grep -q '^evdi'; then
    sudo modprobe evdi
    record module evdi
fi

# evdi-dkms does not load the module at boot. Without this, Hermes
# would lose its virtual display after the first reboot.
if ! grep -qsxF evdi /etc/modules /etc/modules-load.d/*.conf; then
    echo "Enabling EVDI at boot..."
    record line "/etc/modules"$'\t'"evdi"
    echo evdi | sudo tee -a /etc/modules >/dev/null
fi

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
# 8. Install Intel VAAPI driver
# ------------------------------------------------------------

echo
echo "=== Checking Intel VAAPI ==="

if ! dpkg -s intel-media-va-driver >/dev/null 2>&1; then
    apt_install intel-media-va-driver
fi

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
    apt_install vainfo
    vainfo || true
fi

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

# ------------------------------------------------------------
# 13. Verify Hermes binary
# ------------------------------------------------------------

echo
echo "=== Hermes version ==="

"$PROJECT_DIR/build/sunshine" --version

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

cat > "$LAUNCHER" <<EOF
[Desktop Entry]
Name=Hermes
Comment=Game streaming server
Exec=$PROJECT_DIR/build/sunshine
Path=$PROJECT_DIR
Terminal=true
Type=Application
Categories=Network;
EOF

chmod +x "$LAUNCHER"

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
ls -lh "$PROJECT_DIR/build/sunshine"

HERMES_BINARY="$(readlink -f "$PROJECT_DIR/build/sunshine")"
if [ "$HERMES_BINARY" != "$PROJECT_DIR/build/sunshine" ]; then
    ls -lh "$HERMES_BINARY"
fi

echo
echo "--- Launcher ---"
ls -lh "$LAUNCHER"

echo
echo "=== Installation completed successfully ==="
echo
echo "Project:"
echo "$PROJECT_DIR"
echo
echo "Start Hermes:"
echo "$PROJECT_DIR/build/sunshine"
echo
echo "Web UI:"
echo "https://localhost:47990"
echo
echo "Launcher:"
echo "Hermes"
echo
echo "Install manifest (used by uninstall.sh):"
echo "$MANIFEST"
