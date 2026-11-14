# Changelog

All notable changes to Screen Spawner are listed here.

## Planned

- An optional **Screen Spawner** app in the top bar: start and stop Hermes, pair a tablet by PIN, disconnect it, switch between extended and mirrored modes, set a scale for the tablet, choose the order of the displays. See the [Roadmap](README.md#roadmap).

## 0.1.1

- Ask before falling back to a Hermes source build, warn that it may take about an hour, and default to Yes (`[Y/n]`).

- Complete corresponding-source archive, dependency/license inventory, third-party license notices and a source download link in the Hermes Web UI.

- Prebuilt patched Hermes packages for amd64 Ubuntu 22.04/24.04/26.04, Linux Mint 22.x and Debian 13, verified with pinned SHA256 checksums; source build fallback and `--build-from-source`.
- The Hermes launcher uses the installed package binary; uninstall removes the package and recorded dependencies.
- Docker build and validation scripts for the modified GPL-3.0 Hermes packages.
- Uninstall preserves essential/protected system packages and their required dependencies, including when they were added during installation on a minimal Debian system.

## 0.1.0

First release.

Without an app of its own: Hermes is started from the application menu and set up in its Web UI.

### Works

- An Android tablet or phone with Moonlight as a wireless second monitor for Linux, extended or mirrored.
- Mouse, keyboard and touch input on the tablet.
- Together with physical monitors: tested with an HDMI monitor, the laptop screen and the tablet as three displays.
- The tablet can be moved in the display settings during a session, and touch input follows it.
- Sound stays on the computer's speakers.

Tested on Ubuntu 22.04, GNOME on X11 and on Wayland, Intel GPU. Installation and uninstallation were tested end to end on clean Ubuntu 22.04, 24.04 and 26.04, Linux Mint 22.2 and Debian 13 systems.

### Fixes for Hermes

`patches/evdi-fix.patch`, applied by `install.sh`:

- desktop freezes with EVDI (`flip_done timed out`) and the kernel log flooding with `Update was already requested`;
- mouse and touch input landing on the wrong screen on X11;
- the input position following the tablet when monitors are rearranged on X11;
- the Mirror layout on X11 and Wayland, and the capture following the tablet's mode change;
- libevdi 1.12 on Ubuntu 22.04.

### Installation

- `install.sh` installs the dependencies, configures EVDI and builds Hermes from a tested revision.
- Works on Ubuntu, Linux Mint and Debian: it uses the system GCC and CMake where they are new enough, and GCC 13 and CMake from snap only on Ubuntu 22.04.
- `uninstall.sh` removes only what `install.sh` added, shows the list and asks first, and keeps Node.js and NVM if they are in use.

### Known issues

- The virtual monitor stays after quitting Moonlight, until Hermes is stopped or the tablet reconnects.
- A VPN on the tablet can block the connection to Hermes.
- Hermes does not start automatically after a reboot.
- One virtual monitor at a time: a second device joins the same session and shows the same screen.
