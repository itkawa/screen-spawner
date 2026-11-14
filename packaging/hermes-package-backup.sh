#!/usr/bin/env bash
# Run before the owner's live uninstall/reinstall test.
set -euo pipefail
umask 077
backup="$HOME/hermes-backup-$(date +%Y%m%d-%H%M%S)"
mkdir "$backup"
if [ -d "$HOME/.config/hermes" ]; then
    cp -a "$HOME/.config/hermes" "$backup/hermes"
else
    echo 'No existing Hermes config directory.'
fi
if [ -d "$HOME/.local/state/screen-spawner" ]; then
    cp -a "$HOME/.local/state/screen-spawner" "$backup/screen-spawner-state"
fi
if [ -f "$HOME/.local/share/applications/hermes.desktop" ]; then
    cp -a "$HOME/.local/share/applications/hermes.desktop" "$backup/hermes.desktop"
fi
printf 'Backup saved to: %s\n' "$backup"
echo 'Stop Hermes before uninstalling. Pairings remain in ~/.config/hermes.'
echo 'Next, from the screen-spawner repository: ./uninstall.sh, then ./install.sh.'
echo 'Check X11 and Wayland: picture, touch, screen rearrangement and mirroring.'
