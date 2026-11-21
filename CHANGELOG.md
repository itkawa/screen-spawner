# Changelog

All notable changes to Screen Spawner are listed here.

## Planned

- Disconnect the tablet from the app; a scale for the tablet alone; mirroring at a lower resolution; sound by screen; the order of the displays. See the [Roadmap](README.md#roadmap).
- Touch per device and a choice of how the tablet's touches act; sound per device.

## Unreleased

- `uninstall.sh` rebuilds an icon cache in `~/.local/share/icons` if another program made one there, so that it no longer lists the app's removed icons; otherwise Screen Spawner installed afterwards as a package showed an empty icon.

## 0.3.1

### Fedora and Arch Linux

- `install.sh` and `uninstall.sh` work on **Fedora 45** (dnf) and **Arch Linux** (pacman) as well as on Ubuntu, Linux Mint and Debian.
- On Fedora, EVDI comes from the negativo17 Multimedia repository, added for its two EVDI packages only (`dkms-evdi`, `libevdi`); `uninstall.sh` removes the repository and its signing key again.
- On Arch Linux, the installer builds `evdi-dkms` from the AUR with `makepkg`. It does not upgrade the system: upgrade it first with `sudo pacman -Syu`.
- The installer records only the packages it asks dnf or pacman for; on removal they take the dependencies they pulled in with them, and a package that something else still needs stays.
- Hermes packages for Fedora 45 (RPM) and Arch Linux (`.pkg.tar.zst`) in the builds release v0.2.1, with the same patch as the Debian packages plus Hermes #118 (`patches/openssl4.patch`), which both need for OpenSSL 4. The Debian and Ubuntu packages are unchanged (v0.2.0).
- A source build (`--build-from-source`) stays available on Debian and Ubuntu only.

### Install with the package manager

- Screen Spawner is a package now: `sudo apt install screen-spawner` on Ubuntu, Linux Mint and Debian, `sudo dnf install screen-spawner` on Fedora, after adding the [package repository](https://github.com/itkawa/screen-spawner-packages) with one command. It updates with the system and uninstalls with the package manager.
- The package installs the app system-wide (`/usr/share/screen-spawner`, the `screen-spawner` command, the menu entry), with Hermes (`hermes-screen-spawner`, the same packages as builds v0.2.0 and v0.2.1) and EVDI as dependencies, and sets EVDI up for four devices, loaded at boot. Removing it (`purge` on Debian) also removes the EVDI setting it created.
- The APT and DNF repositories are signed (key `280E 1BCC 0414 3CB4 07AB 28C1 E906 9072 32FE 0F54`).
- `install.sh` stays for installing without a repository.

### Also

- Installed from a package, the app runs Hermes from `/usr/bin/sunshine` and passes `stream_audio=false` unless `~/.config/hermes/hermes.conf` sets it, so the sound stays on the computer's speakers as with `install.sh`. **Uninstall Screen Spawner…** shows the package manager command instead.
- The app's hint for a missing EVDI driver no longer names Ubuntu's boot menu.

## 0.3.0

### Several devices at once

- Each tablet or phone gets a screen of its own, all on one desktop: windows move between them as between physical monitors. Up to four devices at once by default.
- One device leaving no longer disconnects the others, and Moonlight no longer says that the session was started on another device.
- Coming back to Moonlight after it went to the background no longer fails with error 503.

### The app

- **Extended**, **Mirrored** for all devices, or **Per device**: each device shows its own screen or mirrors any of the computer's monitors: the built-in display or an external one. The choice is kept for every device.
- **Devices at once**: how many devices can connect at the same time. It asks for the administrator password and takes effect after a restart.
- Before starting Hermes the app checks the EVDI driver and, if it is missing (for example after a kernel update), says what to do. It does not start a second Hermes. If GNOME refuses a new display layout, the previous one comes back.
- On X11 a device's screen switches with `xrandr`, in two steps: the monitors move first and the X screen shrinks after that. Before, the HDMI monitor went off for a moment, which on recent Intel graphics restarts the laptop panel: switching to a mirror took 4–5 s and the laptop screen blinked three times. Now it takes about 0.2 s.
- The display modes and the devices are in one frame, and pairing and **Devices at once** in one row.
- New icons: the penguin with two monitors, and two monitors in the top bar.

### Hermes

The Hermes packages (`0.5.1+ss0.2.0`, builds release v0.2.0) add to `patches/evdi-fix.patch`:

- a virtual display for each connected device, and ending only the session of the device that leaves;
- the device's name, a serial number that stays the same between connections, and the sizes of all monitors in the virtual display's EDID, so GNOME recognises the device and it can mirror any monitor;
- on X11, the monitor sizes come from the X server at once instead of from GNOME, which could take 22 s while GNOME was rearranging the displays, so a second device failed to connect.

The packages now depend on `x11-xserver-utils` and `libglib2.0-bin` (`xrandr` and `gdbus`, which Hermes calls).

### Also

- `install.sh` makes four EVDI devices at boot instead of one, unless another number was chosen; when EVDI is already loaded with fewer, it asks to restart the computer.
- The README describes what the installer changes on the system, and why the kernel's "tainting kernel" line about the EVDI module is expected.

## 0.2.0

### The Screen Spawner app

A window and a top bar icon, installed by `install.sh` with a launcher in the application menu:

- start and stop Hermes; Hermes runs only while the app runs, and **Quit**, Ctrl+C in a terminal or the app ending stop it;
- pair a tablet or phone by the PIN Moonlight shows; the app gives the new device the permissions it needs, so it is no longer refused when it starts the desktop;
- remove paired devices;
- switch a connected tablet between extended and mirrored at once, without disconnecting it; the choice is also kept for the next connection;
- turn on the virtual display of the Desktop app by itself, so no setup in the Hermes Web UI is needed;
- an **Activity** tab, while it is open: the encoder, frame rate, bitrate, encoding time and dropped frames, the CPU temperature, graphics and CPU load, and the Hermes log as it is written;
- open the Hermes Web UI; uninstall Screen Spawner;
- optionally open at login, in the top bar without the window, and optionally start Hermes then too; both are off until you tick them;
- closing the window keeps the app in the top bar; opening it again from the menu shows the same window;
- a short journal in `~/.local/state/screen-spawner/app.log`.

### Hermes

The Hermes packages (`0.5.1+ss0.1.1`, rebuilt) carry three more fixes in `patches/evdi-fix.patch`:

- Hermes no longer encodes the same picture again and again: when nothing on the tablet's screen changes, it sends a new frame only at its minimum rate instead of the full frame rate. On an idle desktop Hermes now encodes 18 instead of 53 frames a second and uses 9% of one CPU thread instead of 22%; with a video on the tablet, 21% instead of about 40%. The mouse in mirrored mode no longer lags.
- Switching between extended and mirrored restarts the video encoder once instead of twice, so the tablet pauses only once.
- Quitting Hermes from its Web UI no longer crashes it when shutting down takes more than five seconds, as closing the virtual display can on Wayland.

### Also

- New app icon.
- `uninstall.sh` closes a running app first and removes the app, its icons, launcher and journal. It never removes the Hermes settings and pairings in `~/.config/hermes`.
- `install.sh` no longer records a new package that another kept new package depends on (on Debian: `libss2`, needed by `e2fsprogs`), and no longer keeps a new package only because a package it recorded itself depends on it, so uninstall does not stop on them. Checking the new packages takes one `apt-cache` call instead of one per package.
- The README describes the app and is installed with it; [docs/performance.md](docs/performance.md) has load, temperature and Wi-Fi measurements, taken with `tools/measure-load.py`.

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
