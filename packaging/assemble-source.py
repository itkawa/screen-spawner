#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Assemble the corresponding-source tree from the retained build export.

Usage: assemble-source.py SOURCE_STAGE BUILD_DEPS_RECIPES VUE_SOURCE I18N_SOURCE
SOURCE_STAGE is produced by the build-container source export. This command
never reads the owner's live Hermes installation or private configuration.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

stage, recipes, vue, i18n = [Path(p).resolve() for p in sys.argv[1:]]
project = Path(__file__).resolve().parents[1]
assert (stage / 'Hermes/VERSION').read_text().strip() == '0.5.1'
assert (stage / 'Hermes/third-party/build-deps/dist/Linux-x86_64').is_dir()

def git_revision(path):
    return subprocess.check_output(['git', '-c', f'safe.directory={path}', '-C', str(path), 'rev-parse', 'HEAD'], text=True).strip()

def copy_source(src, dst, skip_amf=False):
    def ignore(directory, names):
        ignored = [n for n in names if n in {'.git', '__pycache__'}]
        if skip_amf and Path(directory) == src / 'third-party/FFmpeg':
            ignored.append('AMF')
        return ignored
    shutil.copytree(src, dst, dirs_exist_ok=True, ignore=ignore)

# Non-target prebuilt libraries are neither needed nor redistributed here.
dist = stage / 'Hermes/third-party/build-deps/dist'
for path in dist.iterdir():
    if path.name != 'Linux-x86_64':
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink()

vendor = stage / 'fetched-sources'
copy_source(recipes, vendor / 'ffmpeg-build-deps', skip_amf=True)
amf = vendor / 'ffmpeg-build-deps/third-party/FFmpeg/AMF'
copy_source(recipes / 'third-party/FFmpeg/AMF/amf/public/include', amf / 'amf/public/include')
for filename in ['LICENSE.txt', 'README.md']:
    src = recipes / 'third-party/FFmpeg/AMF' / filename
    if src.is_file():
        shutil.copy2(src, amf / filename)
copy_source(vue, vendor / 'vue-core-3.5.22')
copy_source(i18n, vendor / 'vue-i18n-11.1.12')
copy_source(project / 'packaging', stage / 'build-support/packaging')
copy_source(project / 'patches', stage / 'build-support/patches')
for name in ['install.sh', 'uninstall.sh', 'README.md', 'CHANGELOG.md', 'LICENSE']:
    shutil.copy2(project / name, stage / 'build-support' / name)

components = [
    {'name':'Hermes', 'version':'0.5.1', 'revision':'7de12dc2d1c009c5cc4c0e67b8c537ea9e370e99', 'license':'GPL-3.0-only', 'path':'Hermes', 'modified':'patches/evdi-fix.patch'},
    {'name':'Boost', 'version':'1.89.0', 'license':'BSL-1.0', 'path':'fetched-sources/boost-1.89.0'},
    {'name':'nlohmann/json', 'version':'3.11.3', 'license':'MIT', 'path':'fetched-sources/nlohmann-json-3.11.3'},
    {'name':'FFmpeg build recipes', 'revision':git_revision(recipes), 'license':'MIT (recipes only; component licenses apply to libraries)', 'path':'fetched-sources/ffmpeg-build-deps'},
    {'name':'Vue', 'version':'3.5.22', 'revision':git_revision(vue), 'license':'MIT', 'path':'fetched-sources/vue-core-3.5.22'},
    {'name':'vue-i18n', 'version':'11.1.12', 'revision':git_revision(i18n), 'license':'MIT', 'path':'fetched-sources/vue-i18n-11.1.12'},
    {'name':'shared-web', 'version':'2025.922.181114', 'license':'AGPL-3.0-only', 'path':'fetched-sources/npm-node_modules/@lizardbyte/shared-web', 'preferred_source':'src/'},
]
paths = [('AMF headers','AMF','MIT (see original notices)'),('FFmpeg','FFmpeg','GPL-2.0-or-later configuration'),('SVT-AV1','SVT-AV1','BSD-2-Clause + AOM patent license'),('nv-codec-headers','nv-codec-headers','MIT'),('x264','x264','GPL-2.0-or-later'),('x265/HDR10+','x265_git','GPL-2.0-or-later and component notices')]
for name, directory, license in paths:
    components.append({'name':name, 'revision':git_revision(recipes / 'third-party/FFmpeg' / directory), 'license':license, 'path':'fetched-sources/ffmpeg-build-deps/third-party/FFmpeg/'+directory})

npm = []
for directory, dirs, files in os.walk(vendor / 'npm-node_modules'):
    dirs[:] = [d for d in dirs if d != '.git']
    if 'package.json' not in files:
        continue
    p = Path(directory) / 'package.json'
    try:
        data = json.loads(p.read_text())
    except (ValueError, UnicodeError):
        continue
    if data.get('name') and data.get('version'):
        npm.append({'name':data['name'], 'version':data['version'], 'license':data.get('license'), 'path':str(p.parent.relative_to(stage)), 'repository':data.get('repository')})
locks = {}
for p in sorted((stage / 'build-support').glob('package-lock.*.json')):
    locks[p.name] = hashlib.sha256(p.read_bytes()).hexdigest()
assert len(locks) == 4 and len(set(locks.values())) == 1

manifest = {
    'release':'Screen Spawner 0.1.1',
    'modified_by':'itkawa', 'modified_on':'2026-11-12',
    'source_offer':'https://github.com/itkawa/screen-spawner-hermes-builds/releases/download/v0.1.1/hermes-screen-spawner-0.1.1-source.tar.xz',
    'components':components, 'npm_packages':sorted(npm,key=lambda p:(p['name'],p['version'],p['path'])),
    'npm_lock_sha256':locks,
    'provenance':{
        'hermes_submodules':'build-support/HERMES-SUBMODULES.txt',
        'actual_hermes_patch':'build-support/ACTUAL-HERMES-CHANGES.patch',
        'binary_dependencies_snapshot':'b402120705e60b321a5e9c8378fca8dd6eb28b72',
        'ffmpeg_embedded_version':'6400860',
        'recipe_selection':'Pinned historical recipe with matching FFmpeg commit, x264/x265/SVT versions, public headers and embedded Linux configure options; see build-support/header-provenance.log.',
        'system_libraries':'Provided by target distribution; not part of this source archive.',
        'compiler_runtime':'Jammy static GCC13 runtime uses GCC Runtime Library Exception; notice included.',
        'reproducibility':'Preferred-form source and build control inputs are provided; byte-identical binaries across compiler/tool versions are not promised.'
    }
}
(stage / 'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
print(f'Assembled {len(components)} major source components and {len(npm)} npm package records')
