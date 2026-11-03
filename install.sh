#!/usr/bin/env bash

set -e

echo "=== Apollo-Linux / Hermes + EVDI installation ==="

PROJECT_DIR="$HOME/Apollo-Linux"
LAUNCHER="$HOME/.local/share/applications/hermes.desktop"

# ------------------------------------------------------------
# 1. Install EVDI
# ------------------------------------------------------------

echo
echo "=== Checking EVDI ==="

if ! dpkg -s evdi-dkms >/dev/null 2>&1 || \
   ! dpkg -s libevdi0 >/dev/null 2>&1 || \
   ! dpkg -s libevdi-dev >/dev/null 2>&1; then

    sudo apt update
    sudo apt install -y evdi-dkms libevdi0 libevdi-dev
fi

if ! dpkg -s "linux-headers-$(uname -r)" >/dev/null 2>&1; then
    sudo apt install -y "linux-headers-$(uname -r)"
fi

# EVDI must provide at least one pre-created virtual DRM device.
# This allows Hermes to use an existing device without requiring
# root access to /sys/devices/evdi/add.
EVDI_MODPROBE_CONFIG="/etc/modprobe.d/evdi.conf"

if [ ! -f "$EVDI_MODPROBE_CONFIG" ] || \
   ! grep -qxF 'options evdi initial_device_count=1' "$EVDI_MODPROBE_CONFIG"; then

    echo "Configuring EVDI with one initial virtual display..."
    echo 'options evdi initial_device_count=1' | sudo tee "$EVDI_MODPROBE_CONFIG" >/dev/null
fi

if ! lsmod | grep -q '^evdi'; then
    sudo modprobe evdi
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
fi

cd "$PROJECT_DIR"

# Initialize and update submodules
git submodule update --init --recursive

# ------------------------------------------------------------
# 3. Install build dependencies
# ------------------------------------------------------------

echo
echo "=== Installing build dependencies ==="

sudo apt update

sudo apt install -y \
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

    if ! grep -q "ubuntu-toolchain-r/test" \
        /etc/apt/sources.list.d/*.list \
        /etc/apt/sources.list \
        2>/dev/null; then

        sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
        sudo apt update
    fi

    sudo apt install -y gcc-13 g++-13
fi

# ------------------------------------------------------------
# 5. Install CMake if needed
# ------------------------------------------------------------

echo
echo "=== Checking CMake ==="

if ! command -v cmake >/dev/null 2>&1; then
    sudo snap install cmake --classic
fi

# ------------------------------------------------------------
# 6. Install / load NVM
# ------------------------------------------------------------

echo
echo "=== Checking NVM ==="

export NVM_DIR="$HOME/.nvm"

if [ ! -s "$NVM_DIR/nvm.sh" ]; then

    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi

source "$NVM_DIR/nvm.sh"

# ------------------------------------------------------------
# 7. Install Node.js 22 if needed
# ------------------------------------------------------------

echo
echo "=== Checking Node.js 22 ==="

if ! nvm ls 22 | grep -q "v22"; then
    nvm install 22
fi

nvm use 22

# ------------------------------------------------------------
# 8. Install Intel VAAPI driver
# ------------------------------------------------------------

echo
echo "=== Checking Intel VAAPI ==="

if ! dpkg -s intel-media-va-driver >/dev/null 2>&1; then
    sudo apt install -y intel-media-va-driver
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
    sudo apt install -y vainfo
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

LIBEVDI_ROOT="$PROJECT_DIR/build/libevdev-1.13.2/src/libevdev"
LIBEVDI_BUILD="$PROJECT_DIR/build/libevdev-1.13.2/src/libevdev-build"
LIBEVDI_ARCHIVE="$LIBEVDI_ROOT/libevdev-1.13.2.tar.xz"
LIBEVDI_SOURCE="$LIBEVDI_ROOT/libevdev-1.13.2"
LIBEVDI_LIBRARY="$LIBEVDI_BUILD/libevdev/.libs/libevdev.a"

if [ ! -f "$LIBEVDI_LIBRARY" ]; then

    mkdir -p "$LIBEVDI_ROOT"

    if [ ! -f "$LIBEVDI_ARCHIVE" ]; then
        wget \
            -O "$LIBEVDI_ARCHIVE" \
            https://www.freedesktop.org/software/libevdev/libevdev-1.13.2.tar.xz
    fi

    if [ ! -d "$LIBEVDI_SOURCE" ]; then
        tar -xf "$LIBEVDI_ARCHIVE" -C "$LIBEVDI_ROOT"
    fi

    cd "$LIBEVDI_SOURCE"

    if [ ! -f "libevdev/.libs/libevdev.a" ]; then
        ./configure
        make -j"$(nproc)"
    fi

    mkdir -p "$LIBEVDI_BUILD/libevdev/.libs"

    cp \
        "libevdev/.libs/libevdev.a" \
        "$LIBEVDI_LIBRARY"
fi

# ------------------------------------------------------------
# 12. Build Hermes
# ------------------------------------------------------------

echo
echo "=== Building Hermes ==="

cd "$PROJECT_DIR"

ninja -C build -j1

# ------------------------------------------------------------
# 13. Install runtime assets
# ------------------------------------------------------------

echo
echo "=== Installing runtime assets ==="

if [ -d "$PROJECT_DIR/build/assets" ]; then
    sudo mkdir -p /usr/local/assets
    sudo cp -r "$PROJECT_DIR/build/assets/." /usr/local/assets/
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
ls -lh \
    "$PROJECT_DIR/build/sunshine" \
    "$PROJECT_DIR/build/sunshine-0.5.1"

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
