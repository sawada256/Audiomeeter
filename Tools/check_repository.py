#!/usr/bin/env python3
"""Fail if release source tracking contains private/runtime/build artifacts."""
from pathlib import Path
import subprocess, sys
root = Path(__file__).resolve().parent.parent
paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
errors = []
for name in filter(None, paths):
    p = Path(name)
    if any(x in {'.build', '.DS_Store', 'node_modules'} or x.endswith(('.app', '.driver')) for x in p.parts):
        errors.append(name)
    if p.suffix.lower() in {'.log', '.p12', '.pem', '.wav', '.m4a', '.sample'} or p.name in {'settings.json', 'plugin-catalog.json'}:
        errors.append(name)
    if p.suffix in {'.swift', '.c', '.cpp', '.mm', '.sh', '.json'}:
        data = (root / p).read_text()
        if '/Users/' in data or 'BEGIN PRIVATE KEY' in data:
            errors.append(name + ': personal path or private key')
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print('Repository source hygiene checks passed')
