#!/usr/bin/env python3
"""Prepare the shared static website for ChatGPT Sites packaging."""
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
subprocess.run([sys.executable, str(root / 'scripts/check-site.py')], check=True)
output = root / 'dist'
if output.is_symlink():
    raise SystemExit('Refusing to replace a symlink at dist/')
if output.exists():
    shutil.rmtree(output)
shutil.copytree(root / 'site', output)
print('Prepared dist/ from the validated site/ assets.')
