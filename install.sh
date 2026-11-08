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

STATE_DIR="$HOME/.local/state/smart-device-display"
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

    git clone https://github.com/MrOz59/Apollo-Linux "$PROJECT_DIR"
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
    libnuma-dev \
    libgbm-dev \
    qtbase5-dev \
    libqt5svg5-dev \
    ninja-build

# ------------------------------------------------------------
# 4. Install GCC 13 if needed
# ------------------------------------------------------------

echo
echo "=== Checking GCC 13 ==="

if ! command -v gcc-13 >/dev/null 2>&1 || \
   ! command -v g++-13 >/dev/null 2>&1; then

    # The toolchain PPA is added only when gcc-13 is not available in the
    # standard repositories (it is on Ubuntu 24.04+). Besides gcc-13 the PPA
    # also upgrades system libraries such as libstdc++6 and libgcc-s1.
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

# ------------------------------------------------------------
# 5. Install CMake if needed
# ------------------------------------------------------------

echo
echo "=== Checking CMake ==="

if ! command -v cmake >/dev/null 2>&1; then
    sudo snap install cmake --classic
    record snap cmake
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

cmake -B build -G Ninja -S . \
    -DSUNSHINE_ENABLE_CUDA=OFF \
    -DCUDA_FAIL_ON_MISSING=OFF \
    -DCMAKE_C_COMPILER=/usr/bin/gcc-13 \
    -DCMAKE_CXX_COMPILER=/usr/bin/g++-13

# ------------------------------------------------------------
# 11. Fix bundled libevdev if necessary
# ------------------------------------------------------------

echo
echo "=== Checking libevdev ==="

LIBEVDEV_ROOT="$PROJECT_DIR/build/libevdev-1.13.2/src/libevdev"
LIBEVDEV_BUILD="$PROJECT_DIR/build/libevdev-1.13.2/src/libevdev-build"
LIBEVDEV_ARCHIVE="$LIBEVDEV_ROOT/libevdev-1.13.2.tar.xz"
LIBEVDEV_SOURCE="$LIBEVDEV_ROOT/libevdev-1.13.2"
LIBEVDEV_LIBRARY="$LIBEVDEV_BUILD/libevdev/.libs/libevdev.a"

if [ ! -f "$LIBEVDEV_LIBRARY" ]; then

    mkdir -p "$LIBEVDEV_ROOT"

    if [ ! -f "$LIBEVDEV_ARCHIVE" ]; then
        wget \
            -O "$LIBEVDEV_ARCHIVE" \
            https://www.freedesktop.org/software/libevdev/libevdev-1.13.2.tar.xz
    fi

    if [ ! -d "$LIBEVDEV_SOURCE" ]; then
        tar -xf "$LIBEVDEV_ARCHIVE" -C "$LIBEVDEV_ROOT"
    fi

    cd "$LIBEVDEV_SOURCE"

    if [ ! -f "libevdev/.libs/libevdev.a" ]; then
        ./configure
        make -j"$(nproc)"
    fi

    mkdir -p "$LIBEVDEV_BUILD/libevdev/.libs"

    cp \
        "libevdev/.libs/libevdev.a" \
        "$LIBEVDEV_LIBRARY"
fi

# ------------------------------------------------------------
# 12. Build Hermes
# ------------------------------------------------------------

echo
echo "=== Building Hermes ==="

cd "$PROJECT_DIR"

# Single job by default: parallel C++ compilation of Hermes can run out
# of memory on laptops. Faster build: BUILD_JOBS=4 ./install.sh
ninja -C build -j"${BUILD_JOBS:-1}"

# ------------------------------------------------------------
# 13. Install runtime assets
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
# 14. Verify Hermes binary
# ------------------------------------------------------------

echo
echo "=== Hermes version ==="

"$PROJECT_DIR/build/sunshine" --version

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
