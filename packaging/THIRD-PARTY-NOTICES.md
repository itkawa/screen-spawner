# Screen Spawner 0.1.1 — Hermes package source and license notices

These packages contain a modified Hermes 0.5.1, upstream revision
`7de12dc2d1c009c5cc4c0e67b8c537ea9e370e99`. Modified by itkawa for Screen Spawner
on 2026-11-12. Changes: `patches/evdi-fix.patch`, packaging, and a corresponding-
source/third-party-notices link added to the generated Web UI HTML pages.
Hermes and the Screen Spawner build/installation scripts are GPL-3.0-only.
Original copyright and licensing notices in each component remain applicable.

The Web UI includes **@lizardbyte/shared-web 2025.922.181114**, which is
**AGPL-3.0-only**. Its preferred-form JS/SCSS sources and AGPL license are in the
corresponding-source archive. GPLv3 section 13 permits combining GPLv3 and
AGPLv3 components; the AGPL network-source requirement applies to the combined
work. The Web UI provides a direct, no-charge source download link.

The complete release source attachment is:

https://github.com/itkawa/screen-spawner-hermes-builds/releases/download/v0.1.1/hermes-screen-spawner-0.1.1-source.tar.xz

It contains the modified Hermes sources, recursive submodule contents, build
scripts, fetched Boost/json sources, web dependencies/preferred-form sources,
and the FFmpeg/codec source recipes and corresponding pinned revisions.
See the archive's README-SOURCE.md and SOURCE-MANIFEST.json for exact versions
and rebuilding instructions. No registration or additional payment is required.

Major embedded components (preserve each component's complete original notices):

| Component | Version/revision | License |
|---|---|---|
| Hermes / Apollo / Sunshine code | 0.5.1, 7de12dc | GPL-3.0-only |
| Screen Spawner patch/build/install scripts | 0.1.1 | GPL-3.0-only |
| shared-web | 2025.922.181114 | AGPL-3.0-only |
| Boost | 1.89.0 | Boost Software License 1.0 |
| nlohmann/json | 3.11.3 | MIT |
| FFmpeg and libcbs | 6400860b9d4bec5ace91ec3a5e43ad76f9660579, with build-deps patches | GPL-2.0-or-later configuration |
| x264 | b35605ace3ddf7c1a5d67a2eb553f034aef41d55 | GPL-2.0-or-later |
| x265 / HDR10+ code | 1d117bed4747758b51bd2c124d738527e30392cb | GPL-2.0-or-later and component notices |
| SVT-AV1 | efc905a7c2ed155b3654d7968173622734eeb0c0 | BSD-2-Clause and AOM patent license |
| Vue | 3.5.22 | MIT |
| vue-i18n | 11.1.12 | MIT |
| Bootstrap | 5.3.8 | MIT |
| Font Awesome Free | 7.0.1 | Icons CC-BY-4.0, fonts OFL-1.1, code MIT |

This table is an index, not a replacement for the complete licenses. The
archive retains original license files and provides an inventory for additional
submodules and npm components. Their original authors retain their copyrights.
System libraries are supplied by the target Linux distribution; the compiler
runtime on Ubuntu 22.04 uses the GCC Runtime Library Exception.

The software is provided without warranty to the extent permitted by the
applicable licenses. You may modify and redistribute it under those licenses.
