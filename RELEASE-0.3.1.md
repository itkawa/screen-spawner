Title: Screen Spawner 0.3.1 — Fedora and Arch Linux
Tag: v0.3.1

---

Screen Spawner now installs on **Fedora 45** and **Arch Linux** too, with the same one command as on Ubuntu, Linux Mint and Debian.

## What's new

- **Fedora 45:** `install.sh` uses dnf. EVDI comes from the [negativo17](https://negativo17.org) Multimedia repository, which the installer adds for its two EVDI packages only (`dkms-evdi`, `libevdi`), so it never replaces anything else; `uninstall.sh` removes the repository and its signing key again.
- **Arch Linux:** `install.sh` uses pacman and builds `evdi-dkms` from the AUR with `makepkg`, as an AUR helper would. It does not upgrade the system: run `sudo pacman -Syu` first (and restart if the kernel was updated).
- **Clean removal on both:** the installer records only the packages it asked for; on removal dnf and pacman take along the dependencies they pulled in, and a package that something else still needs stays.
- Hermes packages for Fedora 45 (RPM) and Arch Linux in the builds release **v0.2.1**: the same Hermes patch as the Debian packages, plus Hermes [#118](https://github.com/MrOz59/Hermes/pull/118) for OpenSSL 4, which both systems ship.

Nothing changes on Ubuntu, Linux Mint and Debian: the same Hermes packages (builds v0.2.0) and the same installation.

## Installation

```bash
git clone https://github.com/itkawa/screen-spawner
cd screen-spawner
./install.sh
```

Updating from 0.3.0: run `git pull` in the `screen-spawner` folder, then `./install.sh`.

## Tested

The full installation and removal were tested in clean containers on Fedora 45, Arch Linux, Ubuntu 22.04, 24.04 and 26.04, Linux Mint 22 and Debian 13, including a real DKMS build of EVDI on Fedora and Arch. A container has no desktop: streaming on Fedora and Arch Linux has not been tried yet. If you try it, I'd be glad to hear how it went.

## Nuances

- Building from source (`--build-from-source`) stays available on Debian and Ubuntu only.
- Arch Linux is rolling: if a later system upgrade breaks Hermes, a rebuilt package follows.
