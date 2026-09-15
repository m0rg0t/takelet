#!/usr/bin/env python3
"""Check the Git index for accidental local artifacts before publishing."""
from pathlib import Path
import re
import subprocess
import sys

paths = subprocess.check_output(['git', 'ls-files', '-z']).decode().split('\0')
problems = []
for name in filter(None, paths):
    path = Path(name)
    if any(part in {'.local', 'artifacts', '.build', 'build', 'dist'} for part in path.parts):
        problems.append(f'{name}: local artifact is tracked')
    if path.suffix.lower() in {'.mov', '.mp4', '.m4a', '.wav', '.sqlite', '.dmg', '.p12', '.p8'} or path.name.startswith('.env'):
        problems.append(f'{name}: recording, database, or environment file is tracked')
    data = subprocess.check_output(['git', 'show', f':{name}'])
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        continue
    if re.search(r'/(?:Users|Volumes)/[^\s"\'<>]+', text):
        problems.append(f'{name}: machine-specific absolute path')
    if re.search(r'(?i)(?:gh[pousr]_[a-z0-9]{30,}|sk-[a-z0-9_-]{30,}|-----BEGIN (?:RSA |OPENSSH )?PRIVATE KEY-----)', text):
        problems.append(f'{name}: possible credential')
if problems:
    print('\n'.join(problems), file=sys.stderr)
    sys.exit(1)
print(f'Checked {len(list(filter(None, paths)))} indexed files: no local artifacts or obvious credentials.')
