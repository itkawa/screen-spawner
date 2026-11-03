#!/usr/bin/env bash

set -e

echo "=== Safe Apollo-Linux / Hermes rollback ==="

# Stop Hermes if it is running
pkill -TERM -f 'build/sunshine' 2>/dev/null || true
sleep 1

# Remove Apollo-Linux source tree and build
rm -rf "$HOME/Apollo-Linux"

# Remove Hermes desktop launcher
rm -f "$HOME/.local/share/applications/hermes.desktop"

# Remove Hermes runtime assets installed outside the project
sudo rm -rf /usr/local/assets

# Unload EVDI before removing it
sudo modprobe -r evdi 2>/dev/null || true

# Remove EVDI
sudo apt purge -y \
    evdi-dkms \
    libevdi0 \
    libevdi-dev

# Remove GCC 13 installed for this build
sudo apt purge -y \
    gcc-13 \
    g++-13

# Remove the toolchain PPA added for GCC 13
sudo add-apt-repository --remove -y ppa:ubuntu-toolchain-r/test || true

# Remove CMake installed through Snap
if snap list cmake >/dev/null 2>&1; then
    sudo snap remove cmake
fi

# Remove NVM and Node.js installed through NVM
rm -rf "$HOME/.nvm"

# Remove NVM initialization lines from .bashrc
if [ -f "$HOME/.bashrc" ]; then
    sed -i '/NVM_DIR.*\.nvm/d' "$HOME/.bashrc"
    sed -i '/nvm\.sh/d' "$HOME/.bashrc"
    sed -i '/bash_completion.*nvm/d' "$HOME/.bashrc"
fi

# Refresh package metadata
sudo apt update

echo
echo "=== Safe rollback completed ==="
echo
echo "Removed:"
echo "- Apollo-Linux / Hermes source and build"
echo "- Hermes desktop launcher"
echo "- Hermes runtime assets"
echo "- EVDI"
echo "- GCC 13"
echo "- Toolchain PPA"
echo "- CMake Snap"
echo "- NVM / Node.js installed through NVM"
echo
echo "Development libraries and unrelated system packages were NOT removed."
echo "apt autoremove was NOT used."