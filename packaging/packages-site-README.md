# Screen Spawner packages

Packages for [Screen Spawner](https://github.com/itkawa/screen-spawner): an Android tablet or phone as a second, third or further monitor for Linux over Wi-Fi, through the Moonlight app. This repository serves the APT and DNF repositories (GitHub Pages), and its [Releases](https://github.com/itkawa/screen-spawner-packages/releases) hold the patched Hermes packages with their complete source.

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

## Hermes builds

`hermes-screen-spawner` is Hermes 0.5.1 ([MrOz59/Hermes](https://github.com/MrOz59/Hermes), revision 7de12dc2d1c009c5cc4c0e67b8c537ea9e370e99) with my EVDI fixes: among them a virtual display for each connected device, so several tablets and phones can be connected at once. The Fedora and Arch Linux packages also carry Hermes #118 for OpenSSL 4. These are unofficial builds, not a Hermes release channel, and may be superseded by official Hermes packages.

Each [release](https://github.com/itkawa/screen-spawner-packages/releases) has the packages for Ubuntu 22.04, 24.04 (also Mint 22), 26.04, Debian 13, Fedora 45 and Arch Linux, `SHA256SUMS`, and a complete corresponding-source archive: original licenses, dependency sources, exact revisions and rebuilding scripts. Release v0.2.2 is for Screen Spawner 0.3.1; older releases stay for older versions. Until 22 November 2026 the releases were in `screen-spawner-hermes-builds`; old links lead here.

Hermes and my build scripts are GPL-3.0-only. The shared-web Web UI component is AGPL-3.0-only; other components retain their original licenses. All required notices and preferred sources are in the source archive. My patch and packaging scripts: https://github.com/itkawa/screen-spawner/tree/v0.3.1/packaging
