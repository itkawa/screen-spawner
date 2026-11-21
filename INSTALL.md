# Installing Screen Spawner

All the ways to install, update and remove Screen Spawner, on one page. More detail: [Installation](README.md#installation) in the README.

## Ubuntu, Linux Mint, Debian

Ubuntu 22.04, 24.04 and 26.04, Linux Mint 22, Debian 13 (amd64):

```bash
curl -fsSL https://itkawa.github.io/screen-spawner-packages/install-repo.sh | sudo sh
sudo apt install screen-spawner
```

The first line adds the signed Screen Spawner package repository and nothing else. The second installs the app with Hermes and the EVDI driver.

* Update: `sudo apt upgrade`
* Remove: `sudo apt remove screen-spawner`, then `sudo apt autoremove` for Hermes and EVDI

## Fedora

Fedora 45 (x86_64):

```bash
curl -fsSL https://itkawa.github.io/screen-spawner-packages/install-repo.sh | sudo sh
sudo dnf install screen-spawner
```

The first line also adds EVDI from [negativo17](https://negativo17.org) (its two EVDI packages only) and installs the headers of the running kernel. dnf asks once to accept the signing keys.

* Update: `sudo dnf upgrade`
* Remove: `sudo dnf remove screen-spawner`

## Arch Linux

Arch Linux and systems built on it install with the installer for now; an AUR package will follow. Upgrade the system first (`sudo pacman -Syu`) and restart if the kernel was updated:

```bash
git clone https://github.com/itkawa/screen-spawner
cd screen-spawner
./install.sh
```

## With the installer, on any of them

`install.sh` works on all the systems above. It records every change it makes, and `uninstall.sh` removes exactly that.

```bash
git clone https://github.com/itkawa/screen-spawner
cd screen-spawner
./install.sh
```

* Update: `git pull`, then `./install.sh`, in the `screen-spawner` folder
* Remove: `./uninstall.sh`, in the same folder

Use one way or the other. To move from `install.sh` to the package, run `./uninstall.sh` first.

## After installing

1. Install [Moonlight](https://play.google.com/store/apps/details?id=com.limelight) on the Android tablet or phone, on the same Wi-Fi network.
2. Open **Screen Spawner** from the application menu and press **Start**.
3. In Moonlight, tap the computer, then press **Pair a device…** in the app and enter the PIN Moonlight shows.
4. In Moonlight, choose **Desktop**.

On plain GNOME, as on Debian or Fedora, also install `gnome-shell-extension-appindicator` for the top bar icon.

Paired devices and Hermes settings in `~/.config/hermes` stay when Screen Spawner is removed, whichever way it was installed.
