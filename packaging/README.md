# Hermes packages for Screen Spawner 0.1.1

Run from the Screen Spawner repository on an amd64 Linux Docker host:

```bash
./packaging/build-deb.sh ubuntu22.04
./packaging/build-deb.sh ubuntu24.04
./packaging/build-deb.sh ubuntu26.04
./packaging/build-deb.sh debian13
```

Builds are serial (a shared `flock` prevents concurrent builds). Each container
has `--memory=6g --cpus=4`; Ninja uses three jobs and retries with one job after
failure. The runner checks `MemAvailable >= 7 GiB` before every build and prints
`free -g`. Stop and consult the owner if that check fails. Allow roughly an hour
per system. Never run the installer on the build host.

Outputs: `../packages-0.1.1/`; logs: `../docker-tests/package-build-*.log`.
Override with `PACKAGE_OUTPUT_DIR` and `PACKAGE_LOG_DIR`. Docker volumes named
`ss-package-<system>` preserve source and build objects for a retry. Build
packages are installed only inside the container. Do not delete these volumes
until the results have been reviewed.

Sources: [Hermes](https://github.com/MrOz59/Hermes) at
`7de12dc2d1c009c5cc4c0e67b8c537ea9e370e99`, recursively pinned submodules,
and [`../patches/evdi-fix.patch`](../patches/evdi-fix.patch). The patch is applied
with `git apply`, leaving upstream's commit unchanged. Node 22 is verified
against the Node distribution's SHA256 list. Ubuntu 22.04 uses GCC 13 from the
toolchain PPA, CMake 3.31.6, and static libstdc++/libgcc linkage; other systems
use the system compiler and CMake. CUDA is disabled, as in `install.sh`.

`package-deb.sh` stages CMake's installation and packages the binary, tray icons and
`/usr/share/hermes` assets with CPack DEB. It deliberately excludes upstream's
postinst (which loads uhid, sets CAP_SYS_ADMIN and reloads udev), udev/polkit
rules, sysusers, modules-load files, service units, extra helper programs and
system launchers. The existing installer manages EVDI and the per-user launcher.
No package maintainer scripts run and no service is enabled. Dependencies come
from `dpkg-shlibdeps` plus the runtime-loaded EVDI, X11, Avahi and graphics
libraries, rather than upstream's distribution-specific manual list. On jammy
libevdi0-dev supplies the unversioned .so link that Hermes loads. The package conflicts with `hermes`; it does not Provide or Replace
it. Upgrading to official Hermes requires removing this package first.

The binary's compiled asset path and the staged web directory are checked before
CPack runs. Ubuntu 22.04 additionally rejects direct dependencies on shared
libstdc++ or libgcc. Each resulting package must also pass clean-container
installation, ldd, version, asset, and removal checks before publication.

This is modified GPL-3.0 Hermes. Keep the source revision, patch and build scripts
available alongside every distributed package. These scripts reproduce the
build process; apt/npm repositories are live, so this does not promise
byte-for-byte reproducibility.

## Validation

After all four builds, pin their actual SHA256 values in `install.sh` and write
`../packages-0.1.1/SHA256SUMS`. Do not publish placeholder checksums.

```bash
python3 packaging/check-installer.py
./packaging/test-deb.sh ubuntu22.04 package
./packaging/test-deb.sh ubuntu24.04 package
./packaging/test-deb.sh ubuntu26.04 package
./packaging/test-deb.sh debian13 package
./packaging/test-deb.sh mint22 package
./packaging/test-deb.sh ubuntu22.04 installer
./packaging/test-deb.sh ubuntu24.04 installer
./packaging/test-deb.sh ubuntu26.04 installer
./packaging/test-deb.sh debian13 installer
./packaging/test-deb.sh mint22 installer
./packaging/test-deb.sh ubuntu24.04 source
```

Tests are serial and use the same lock as builds. Containers are retained as
`ss-test-<system>-<mode>` for investigation; use a fresh container for each full
run (remove a previous test container explicitly before repeating). Installer
tests use local package files but still verify the pinned checksums. Kernel
release reporting and modprobe/lsmod are container stand-ins; DKMS compilation
is real, loading modules and desktop streaming are not tested. No privileged
containers or host module directories are used.

## Publication by the owner

Review the logs and changes first. `~/release-packages.sh` (also kept here)
commits the listed files, pushes main and creates the new v0.1.1 tag without force.
The existing v0.1.0 tag and release remain unchanged.
The agent must not run it. Upload the four `.deb` files and `SHA256SUMS` from
`../packages-0.1.1/` to the separate screen-spawner-hermes-builds v0.1.1 release.
Publish the Screen Spawner release afterward with `RELEASE-0.1.1.md`; it links
to the builds release and needs no duplicated binary attachments.

Before testing on the live desktop, stop Hermes and run
`~/hermes-package-backup.sh`. Then run `./uninstall.sh` and `./install.sh` and
check X11/Wayland with the tablet and phone: picture, input, rearrangement and
mirroring. Keep the backup until both modes work. Finally run
`./packaging/verify-release.sh` to check main/tag equality, public release status,
and downloads/checksums. Local containers cannot replace the live test.

To repackage an already completed build without compiling again, run
`./packaging/build-deb.sh SYSTEM --package-only`. This uses the retained build
container and does not change the compiled Hermes revision or patch.


## Corresponding source and Web UI notices

The release must include `hermes-screen-spawner-0.1.1-source.tar.xz` and its
entry in SHA256SUMS. Four DEBs + the source archive + SHA256SUMS are the six
manual release attachments. Do not use only GitHub's automatic repository ZIP
as the Hermes source: it does not contain the complete dependency sources.

`add-source-notice.py` adds the source/third-party-notices links to staged Web UI
HTML. `collect-license-notices.py` preserves original dependency licenses in
the DEB. shared-web is AGPL-3.0-only; its preferred-form sources and license are
included in the source archive and its network-source offer is visible in the UI.
See THIRD-PARTY-NOTICES.md. Compiler/runtime and other component notices remain
applicable under their original terms.

The archive contains the exact patched build source and recursive submodules,
Boost/json/npm inputs, preferred-form Vue/i18n source, pinned historical FFmpeg
and encoder source recipes/revisions, per-system lock files, and a component
manifest. `export-source.sh` exports the original retained `/build/Hermes` tree from a
read-only build-volume mount into `/export` (set EXPORT_UID/EXPORT_GID for output
ownership). `assemble-source.py` then assembles that exported source tree with
the pinned recipe and Vue/i18n source checkouts;
`build-archive.sh` / `container-archive-build.sh` rebuild directly from it,
without fetching application/npm/Boost/json source from the network. The
archive's README-SOURCE.md explains system-tool bootstrap and rebuilding the
prepared codec libraries.

## Separate artifact repository

Publish the four DEBs, corresponding-source archive and SHA256SUMS in
https://github.com/itkawa/screen-spawner-hermes-builds/releases/tag/v0.1.1.
The Screen Spawner v0.1.1 release links there. Full builds require 7 GiB
available; --package-only requires 1 GiB and never compiles Hermes.

## Local build workspace

Set `SCREEN_SPAWNER_BUILDS_DIR` or local Git config `screenSpawner.buildsDirectory`
to keep packages and logs outside the project. Otherwise the default is the
project parent directory. This checkout uses `/home/shared/screen spawner hermes`.
