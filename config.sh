# ------------------------------------------------------------
# Configure EVDI
# ------------------------------------------------------------

echo
echo "=== Configuring EVDI ==="

# Create EVDI module options
echo "options evdi initial_device_count=1" | sudo tee /etc/modprobe.d/evdi.conf >/dev/null

# Disable modules-load.d config if exists
if [ -f /etc/modules-load.d/evdi.conf ]; then
    sudo mv /etc/modules-load.d/evdi.conf /etc/modules-load.d/evdi.conf.disabled
fi

# Add EVDI to classic modules autoload list
if ! grep -qx "evdi" /etc/modules 2>/dev/null; then
    echo "evdi" | sudo tee -a /etc/modules >/dev/null
fi

# Rebuild module dependency database
sudo depmod -a

# Load EVDI now if not loaded
if ! lsmod | grep -q '^evdi'; then
    sudo modprobe evdi
fi

echo "EVDI configured:"
lsmod | grep evdi || true
cat /sys/module/evdi/parameters/initial_device_count 2>/dev/null || true
