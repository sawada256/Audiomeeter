#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Export committed source plus the pinned JUCE tree, without private Git history."""
from pathlib import Path
import argparse, io, subprocess, tarfile
ROOT = Path(__file__).resolve().parent.parent
JUCE_REV = '29396c22c93392d6738e021b83196283d6e4d850'

def export(output):
    if subprocess.check_output(['git','status','--porcelain'],cwd=ROOT).strip():
        raise SystemExit('Commit all source changes before producing a corresponding-source archive.')
    juce = ROOT/'.build/dependencies/JUCE'
    if (juce/'.git').exists():
        revision = subprocess.check_output(['git','rev-parse','HEAD'],cwd=juce,text=True).strip()
    else:
        revision = (juce/'.audiomeeter-source-revision').read_text().strip()
    if revision != JUCE_REV:
        raise SystemExit('Unexpected JUCE revision')
    names = subprocess.check_output(['git','ls-files','-z'],cwd=ROOT).decode().split('\0')
    revision = subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    prefix = 'Audiomeeter-source'
    def anonymous(info):
        info.uid = info.gid = 0; info.uname = info.gname = ''
        return info
    with tarfile.open(output,'w:gz') as archive:
        for name in filter(None,names):
            if name == 'AGENTS.md':
                continue
            archive.add(ROOT/name,arcname=f'{prefix}/{name}',recursive=False,filter=anonymous)
        for path in sorted(juce.rglob('*')):
            relative = path.relative_to(juce)
            if '.git' in relative.parts or not path.is_file():
                continue
            archive.add(path,arcname=f'{prefix}/.build/dependencies/JUCE/{relative}',recursive=False,filter=anonymous)
        for name, data in [('SOURCE_REVISION.txt', revision+'\n'),
                           ('.build/dependencies/JUCE/.audiomeeter-source-revision',JUCE_REV+'\n')]:
            payload = data.encode(); info = tarfile.TarInfo(f'{prefix}/{name}')
            info.size = len(payload); info.mode = 0o644
            archive.addfile(info,io.BytesIO(payload))
    print(output)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('output',type=Path)
    args = parser.parse_args(); args.output.parent.mkdir(parents=True,exist_ok=True); export(args.output)
