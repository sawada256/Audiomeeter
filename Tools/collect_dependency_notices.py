#!/usr/bin/env python3
"""Preserve license/readme notices of the pinned JUCE dependency tree."""
from pathlib import Path
import shutil, sys
source, output = map(Path, sys.argv[1:])
for path in (source / 'modules').rglob('*'):
    if path.is_file() and path.name.lower().startswith(('license', 'licence', 'copying', 'copyright', 'readme')):
        target = output / path.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
