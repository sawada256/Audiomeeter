#!/usr/bin/env python3
"""Preserve license/readme notices of the pinned JUCE dependency tree."""
from pathlib import Path
import shutil, sys
source, output = map(Path, sys.argv[1:])
for path in (source / 'modules').rglob('*'):
    if path.is_file() and any(word in path.name.lower() for word in ('license', 'licence', 'copying', 'copyright', 'readme')):
        target = output / path.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)

# Some JUCE dependency notices live inside headers rather than standalone licenses.
for relative in ["modules/juce_opengl/opengl/juce_gl.h", "modules/juce_box2d/box2d/Box2D.h",
                 "modules/juce_audio_processors_headless/format_types/pslextensions/ipslcontextinfo.h",
                 "modules/juce_javascript/choc/javascript/choc_javascript_QuickJS.h"]:
    path = source / relative
    if path.is_file():
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
