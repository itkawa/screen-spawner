#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Collect original license/notices alongside each packaged binary."""
from pathlib import Path
import os
import sys

output = Path(sys.argv[1])
roots = [Path(p) for p in sys.argv[2:]]
entries = []
for root in roots:
    if not root.exists():
        raise SystemExit(f'Missing license input: {root}')
    for directory, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in {'.git', '__pycache__', '.cache'})
        for filename in sorted(files):
            upper = filename.upper()
            if not upper.startswith(('LICENSE', 'LICENCE', 'COPYING', 'COPYRIGHT', 'NOTICE', 'PATENTS')):
                continue
            path = Path(directory) / filename
            if not path.is_file():
                continue
            data = path.read_bytes()
            if b'\0' in data:
                continue
            entries.append((f'{root.name}/{path.relative_to(root)}', data.decode('utf-8', errors='replace')))
if not entries:
    raise SystemExit('No third-party license files found')
output.parent.mkdir(parents=True, exist_ok=True)
with output.open('w') as file:
    file.write('Original third-party license and copyright notices.\n'
               'Each component retains the terms in its notice below.\n\n')
    for name, text in entries:
        file.write(f'\n===== {name} =====\n{text}\n')
print(f'Collected {len(entries)} third-party license/notice files')
