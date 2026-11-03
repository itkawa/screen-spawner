# ------------------------------------------------------------
# Configure virtual monitor layout
# ------------------------------------------------------------

echo
echo "=== Configuring monitor layout ==="

# Directory for Hermes monitor configuration
MONITOR_CONFIG_DIR="$HOME/.config/hermes"
MONITOR_CONFIG_FILE="$MONITOR_CONFIG_DIR/monitor-layout.conf"

# Create configuration directory
mkdir -p "$MONITOR_CONFIG_DIR"

# Detect connected displays
echo "Detected displays:"
xrandr --query | grep " connected " || true

# Save current monitor layout
# This file will later be used by Hermes to restore the layout automatically
cat > "$MONITOR_CONFIG_FILE" <<EOF
# Hermes virtual monitor layout configuration

[layout]

# Main physical display
# Example: eDP-1
primary=

# Virtual EVDI display
# Example: DVI-I-1
virtual=

# Position of virtual display relative to primary display
# Allowed values:
# right
# left
# above
# below
position=right

# Manual coordinates (optional)
# Used when position is not enough
x=0
y=0

# Virtual display mode
width=1920
height=1080
refresh=60

# Enable automatic layout restore
enabled=true
EOF

echo "Monitor layout configuration created:"
echo "$MONITOR_CONFIG_FILE"

echo
echo "Current monitor configuration:"
cat "$MONITOR_CONFIG_FILE"
