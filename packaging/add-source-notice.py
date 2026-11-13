#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Add the published corresponding-source offer to staged Web UI pages."""
from pathlib import Path
import re
import sys

web = Path(sys.argv[1])
notice = '''<footer id="screen-spawner-source-notice" style="padding:0.75rem;text-align:center;font-size:0.875rem">
Modified Hermes for Screen Spawner 0.1.1 ·
<a href="https://github.com/itkawa/screen-spawner-hermes-builds/releases/download/v0.1.1/hermes-screen-spawner-0.1.1-source.tar.xz" target="_blank" rel="noopener noreferrer">Download corresponding source</a> ·
<a href="https://github.com/itkawa/screen-spawner/blob/v0.1.1/packaging/THIRD-PARTY-NOTICES.md" target="_blank" rel="noopener noreferrer">Licenses and third-party notices</a>
</footer>'''
count = 0
for page in sorted(web.glob('*.html')):
    if page.name.startswith('template_'):
        continue
    text = page.read_text()
    if 'id="screen-spawner-source-notice"' in text:
        updated, matches = re.subn(r'<footer id="screen-spawner-source-notice"[^>]*>.*?</footer>', lambda match: notice, text, flags=re.DOTALL)
        if matches != 1:
            raise SystemExit(f'Unexpected source-notice count: {page}')
        if updated != text:
            page.write_text(updated)
            count += 1
        continue
    if '</body>' not in text:
        raise SystemExit(f'Missing body closing tag: {page}')
    page.write_text(text.replace('</body>', notice + '\n</body>', 1))
    count += 1
if not list(web.glob('*.html')):
    raise SystemExit(f'No Web UI HTML pages in {web}')
print(f'Added corresponding-source notice to {count} Web UI pages')
