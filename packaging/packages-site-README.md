# Screen Spawner packages

APT and DNF repositories for [Screen Spawner](https://github.com/itkawa/screen-spawner): an Android tablet or phone as a second, third or further monitor for Linux over Wi-Fi, through the Moonlight app.

## Ubuntu, Linux Mint, Debian

Ubuntu 22.04, 24.04 and 26.04, Linux Mint 22, Debian 13 (amd64):

```
curl -fsSL https://itkawa.github.io/screen-spawner-packages/install-repo.sh | sudo sh
sudo apt install screen-spawner
```

Updates come with `sudo apt upgrade`. To remove: `sudo apt remove screen-spawner`, then `sudo apt autoremove` for Hermes and EVDI.

## Fedora

Fedora 45 (x86_64):

```
curl -fsSL https://itkawa.github.io/screen-spawner-packages/install-repo.sh | sudo sh
sudo dnf install screen-spawner
```

The first line also adds EVDI from [negativo17](https://negativo17.org) (only its EVDI packages) and installs the running kernel's headers if they are missing. dnf asks once to accept the signing keys. To remove: `sudo dnf remove screen-spawner`.

## Arch Linux

Use [`install.sh`](https://github.com/itkawa/screen-spawner#with-installsh) for now; an AUR package will follow.

## What install-repo.sh changes

It adds the repository and its signing key, and nothing else:

* Ubuntu, Mint, Debian: `/etc/apt/sources.list.d/screen-spawner.sources` and `/usr/share/keyrings/screen-spawner-packages.gpg`
* Fedora: `/etc/yum.repos.d/screen-spawner.repo`, `/etc/yum.repos.d/screen-spawner-evdi.repo`, and `kernel-devel` for the running kernel

To remove the repository, delete these files.

## Signing key

`screen-spawner-packages.asc`, fingerprint `280E 1BCC 0414 3CB4 07AB  28C1 E906 9072 32FE 0F54`.

## Contents

The packages are `screen-spawner` (the app) and `hermes-screen-spawner` (Hermes 0.5.1 with the Screen Spawner patch, GPL-3.0). The Hermes packages and their complete corresponding source are published in [screen-spawner-hermes-builds](https://github.com/itkawa/screen-spawner-hermes-builds/releases).
