# Changelog

All notable changes to Screen Spawner are listed here.

## Planned

- An optional **Screen Spawner** app in the top bar: start and stop Hermes, pair a tablet by PIN, disconnect it, switch between extended and mirrored modes, set a scale for the tablet, choose the order of the displays. See the [Roadmap](README.md#roadmap).

## 0.1.0

First release.

Without an app of its own: Hermes is started from the application menu and set up in its Web UI.

### Works

- An Android tablet with Moonlight as a wireless second monitor for Ubuntu, extended or mirrored.
- Mouse, keyboard and touch input on the tablet.
- Together with physical monitors: tested with an HDMI monitor, the laptop screen and the tablet as three displays.
- The tablet can be moved in the display settings during a session, and touch input follows it.
- Sound stays on the computer's speakers.

Tested on Ubuntu 22.04, GNOME on X11, Intel GPU. Installation and uninstallation were tested end to end on a clean Ubuntu 22.04 system.

### Fixes for Hermes

`patches/evdi-fix.patch`, applied by `install.sh`:

- desktop freezes with EVDI (`flip_done timed out`) and the kernel log flooding with `Update was already requested`;
- mouse and touch input landing on the wrong screen on X11;
- the input position following the tablet when monitors are rearranged on X11;
- the Mirror layout on X11, and the capture following the tablet's mode change;
- libevdi 1.12 on Ubuntu 22.04.

### Installation

- `install.sh` installs the dependencies, configures EVDI and builds Hermes from a tested revision.
- `uninstall.sh` removes only what `install.sh` added, shows the list and asks first, and keeps Node.js and NVM if they are in use.

### Known issues

- The virtual monitor stays after quitting Moonlight, until Hermes is stopped or the tablet reconnects.
- A VPN on the tablet can block the connection to Hermes.
- Hermes does not start automatically after a reboot.
