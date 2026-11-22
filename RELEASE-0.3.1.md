Title: Screen Spawner 0.3.1 — Fedora, Arch Linux and package managers
Tag: v0.3.1

---

Screen Spawner now installs on **Fedora 45** and **Arch Linux** too, and on every supported system it can be installed with the package manager: `apt` on Ubuntu, Linux Mint and Debian, `dnf` on Fedora.

## What's new

- **Fedora 45:** `install.sh` uses dnf. EVDI comes from the [negativo17](https://negativo17.org) Multimedia repository, which the installer adds for its two EVDI packages only (`dkms-evdi`, `libevdi`), so it never replaces anything else; `uninstall.sh` removes the repository and its signing key again.
- **Arch Linux:** `install.sh` uses pacman and builds `evdi-dkms` from the AUR with `makepkg`, as an AUR helper would. It does not upgrade the system: run `sudo pacman -Syu` first (and restart if the kernel was updated).
- **Clean removal on both:** the installer records only the packages it asked for; on removal dnf and pacman take along the dependencies they pulled in, and a package that something else still needs stays.
- Hermes packages for Fedora 45 (RPM) and Arch Linux in the builds release **v0.2.2**: the same Hermes patch as the Debian packages, plus Hermes [#118](https://github.com/MrOz59/Hermes/pull/118) for OpenSSL 4, which both systems ship.
- **Packages:** `screen-spawner` for apt and dnf, with `hermes-screen-spawner` and EVDI as dependencies. The package sets EVDI up for four devices; the app, installed from a package, runs Hermes from `/usr/bin/sunshine`, keeps the sound on the computer, and its **Uninstall** button shows the package manager command.
- **A computer that does not start, fixed and guarded against:** on a fast start the login screen could start before the computer's graphics card was ready, see only EVDI's virtual displays and give up, leaving a black screen. Now it waits for the real graphics card. And if a start ever does not reach the login screen, the next one goes without EVDI, once, and the app says why. How to start without EVDI by hand is in the README (Troubleshooting).
- **Tested with four devices at once**, a tablet and three phones, with a video mirrored to all of them: no frame dropped, the CPU at 38% ([measurements](https://github.com/itkawa/screen-spawner/blob/main/docs/performance.md)).
- **A Hermes fix for all systems** (builds **v0.2.2**): a stream that could not start, for example because another program held its video port, kept Hermes's control port, so every later connection failed with a port error until Hermes was restarted. Now the next connection works.

## Installation

With the package manager, on Ubuntu 22.04, 24.04 and 26.04, Linux Mint 22 and Debian 13:

```bash
curl -fsSL https://itkawa.github.io/screen-spawner-packages/install-repo.sh | sudo sh
sudo apt install screen-spawner
```

On Fedora 45 the same first line, then `sudo dnf install screen-spawner`. Screen Spawner then updates with the system and is removed with the package manager. The first line only adds the signed [package repository](https://github.com/itkawa/screen-spawner-packages) (on Fedora also EVDI from negativo17 and the kernel headers).

Or with the installer, on all of them and on Arch Linux (an AUR package will follow):

```bash
git clone https://github.com/itkawa/screen-spawner
cd screen-spawner
./install.sh
```

Do not mix the two: if Screen Spawner was installed with `install.sh`, run `./uninstall.sh` before installing the package.

Updating from 0.3.0: run `git pull` in the `screen-spawner` folder, then `./install.sh`. Installed from a package, `sudo apt upgrade` or `sudo dnf upgrade` brings the packages `0.3.1-2`.

## Tested

The full installation, upgrade and removal, with `install.sh` and with the packages, were tested in clean containers on Fedora 45, Arch Linux, Ubuntu 22.04, 24.04 and 26.04, Linux Mint 22 and Debian 13, including a real DKMS build of EVDI on Fedora and Arch. A container has no desktop: streaming on Fedora and Arch Linux has not been tried yet. If you try it, I'd be glad to hear how it went.

## Nuances

- Building from source (`--build-from-source`) stays available on Debian and Ubuntu only.
- Arch Linux is rolling: if a later system upgrade breaks Hermes, a rebuilt package follows.
