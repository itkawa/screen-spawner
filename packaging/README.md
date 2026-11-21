# Hermes packages for Screen Spawner 0.3.0

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

Outputs: `../packages-0.2.0/`; logs: `../docker-tests/package-build-*.log`.
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

## Fedora and Arch Linux packages (builds v0.2.1)

`./packaging/build-other.sh fedora45` and `./packaging/build-other.sh arch` build
Hermes in a `fedora:45` or `archlinux:latest` container with the same patch plus
`patches/openssl4.patch` (Hermes #118; both systems ship OpenSSL 4). CMake 4 needs
`-DCMAKE_POLICY_VERSION_MINIMUM=3.5` and, for the fetched Boost, one line in
Boost.Locale's CMakeLists.txt; `container-build-other.sh` adds both.
`package-other.sh` stages the same files as `package-deb.sh` and makes an RPM with
CPack or an Arch package with `makepkg`. Outputs go to `../packages-0.2.1/`.

`./packaging/test-other.sh SYSTEM package` installs, checks and removes the
package; `./packaging/test-other.sh SYSTEM installer` runs `install.sh` and
`uninstall.sh` as a user with sudo, including a real DKMS build of EVDI for the
distribution's current kernel (Fedora: dkms-evdi from negativo17; Arch: evdi-dkms
built from the AUR), and checks that everything recorded is gone afterwards.
Arch Linux is rolling: rebuild and retest its package when its libraries move on.

## Validation

After all four builds, pin their actual SHA256 values in `install.sh` and write
`../packages-0.2.0/SHA256SUMS`. Do not publish placeholder checksums.

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

Review the logs and changes first. The owner publishes; the agent does not.
Create the screen-spawner-hermes-builds release v0.2.0 with the four `.deb`
files, the source archive and `SHA256SUMS` from `../packages-0.2.0/` (packages
0.5.1+ss0.2.0; the v0.1.1 release stays for Screen Spawner 0.2.0). Then push
main, tag v0.3.0 and publish the Screen Spawner release with
`RELEASE-0.3.0.md`; it links to the builds release and needs no duplicated
binary attachments.

Before testing on the live desktop, stop Hermes and run
`~/hermes-package-backup.sh`. Then run `./uninstall.sh` and `./install.sh` and
check X11/Wayland with the tablet and phone: picture, input, rearrangement and
mirroring. Keep the backup until both modes work. Finally run
`./packaging/verify-release.sh` to check main/tag equality, public release status,
and downloads/checksums. Local containers cannot replace the live test.

## Rebuilding for a new package version

Each package version gets its own build container (`ss-package-<system>-<version>`)
on the same `ss-package-<system>` volume. When the volume holds a tree with an
older version of the patch, `container-build.sh` replaces only the files whose
content changes, so the rebuild recompiles just those. `SS_BUILD_MIN_GIB` and
`SS_TEST_MIN_GIB` lower the 7 GiB memory check only when the owner allows it for
such an incremental rebuild. Test containers are removed after each run; the log
keeps the result.

When only the patch and the build scripts changed, make the corresponding-source
archive from the previous one with
`./packaging/refresh-source-archive.sh OLD_ARCHIVE OLD_VERSION NEW_VERSION PACKAGE_DIR`.

To repackage an already completed build without compiling again, run
`./packaging/build-deb.sh SYSTEM --package-only`. This uses the retained build
container and does not change the compiled Hermes revision or patch.


## Corresponding source and Web UI notices

The release must include `hermes-screen-spawner-0.2.0-source.tar.xz` and its
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
https://github.com/itkawa/screen-spawner-hermes-builds/releases/tag/v0.2.0.
The Screen Spawner v0.3.0 release links there. Full builds require 7 GiB
available; --package-only requires 1 GiB and never compiles Hermes.

## Local build workspace

Set `SCREEN_SPAWNER_BUILDS_DIR` or local Git config `screenSpawner.buildsDirectory`
to keep packages and logs outside the project. Otherwise the default is the
project parent directory. This checkout uses `/home/shared/screen spawner hermes`.
