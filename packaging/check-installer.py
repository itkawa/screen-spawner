#!/usr/bin/env python3
"""Exercise package selection and checksum rejection without touching the host."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile

installer = Path(__file__).resolve().parents[1] / 'install.sh'
source = installer.read_text()
functions = source[source.index('select_package() {'):source.index('\nPACKAGE_INSTALLED=0')]
# Replace only the test fixture's os-release location; production stays fixed.
functions = functions.replace('/etc/os-release', '"$TEST_OS_RELEASE"')
fixtures = [
    ('ID=ubuntu\nVERSION_ID=22.04\n', 'ubuntu22.04'),
    ('ID=ubuntu\nVERSION_ID=24.04\n', 'ubuntu24.04'),
    ('ID=ubuntu\nVERSION_ID=26.04\n', 'ubuntu26.04'),
    ('ID=debian\nVERSION_ID=13\n', 'debian13'),
    ('ID=debian\nVERSION_ID=13.1\n', 'debian13'),
    ('ID=linuxmint\nVERSION_ID=22.2\nUBUNTU_CODENAME=noble\n', 'ubuntu24.04'),
    ('ID=pop\nVERSION_ID=22.04\nID_LIKE="ubuntu debian"\nUBUNTU_CODENAME=jammy\n', 'ubuntu22.04'),
    ('ID=ubuntu\nVERSION_ID=25.10\n', ''),
    ('ID=linuxmint\nVERSION_ID=21.3\nUBUNTU_CODENAME=jammy\n', ''),
    ('ID=linuxmint\nVERSION_ID=22.2\nUBUNTU_CODENAME=unexpected\n', ''),
    ('ID=debian\nVERSION_ID=12\n', ''),
]
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    release = root / 'os-release'
    env = dict(os.environ, TEST_OS_RELEASE=str(release))
    prelude = 'set -e\ndpkg() { echo "${TEST_ARCH:-amd64}"; }\n' + functions
    for contents, expected in fixtures:
        release.write_text(contents)
        result = subprocess.run(['bash', '-c', prelude + '\nif select_package; then echo "$PACKAGE_SYSTEM"; fi'],
                                env=env, capture_output=True, text=True, check=True)
        assert result.stdout.strip() == expected, (contents, result.stdout, result.stderr)
    release.write_text('ID=ubuntu\nVERSION_ID=22.04\n')
    result = subprocess.run(['bash', '-c', prelude + '\n! select_package'],
                            env=dict(env, TEST_ARCH='arm64'), check=True)
    package = root / 'hermes-screen-spawner_0.5.1+ss0.1.1_ubuntu22.04_amd64.deb'
    package.write_bytes(b'fixture package; apt is mocked')
    checksum = hashlib.sha256(package.read_bytes()).hexdigest()
    # Replace the actual checksum only in the fixture, whether pending or final.
    import re
    fixture = re.sub(r'(ubuntu22\.04\) PACKAGE_SHA256=")[^"]+', r'\g<1>' + checksum, prelude)
    mocks = '\napt_install() { echo apt-called >> "$TEST_APT_LOG"; }\n'
    logfile = root / 'apt.log'
    testenv = dict(env, SCREEN_SPAWNER_PACKAGE_DIR=str(root), TEST_APT_LOG=str(logfile))
    subprocess.run(['bash', '-c', fixture + mocks + '\ninstall_release_package'], env=testenv,
                   capture_output=True, check=True)
    assert logfile.read_text().splitlines() == ['apt-called']
    logfile.unlink()
    package.write_bytes(b'corrupt')
    subprocess.run(['bash', '-c', fixture + mocks + '\n! install_release_package'], env=testenv,
                   capture_output=True, check=True)
    assert not logfile.exists(), 'apt ran before checksum verification'
    package.unlink()
    subprocess.run(['bash', '-c', fixture + mocks + '\n! install_release_package'], env=testenv,
                   capture_output=True, check=True)
    assert not logfile.exists(), 'apt ran after missing package'
    official = '\ndpkg-query() { printf ii; }\n'
    subprocess.run(['bash', '-c', fixture + mocks + official + '\n! install_release_package'],
                   env=testenv, capture_output=True, check=True)
    assert not logfile.exists(), 'apt ran with a conflicting pre-existing Hermes package'
print('PASS: 11 distribution mappings, unsupported architecture, valid checksum, corrupt/missing packages and an existing official Hermes package')
