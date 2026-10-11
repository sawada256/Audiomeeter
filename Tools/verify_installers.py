#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Verify real package payloads and corresponding source without installing."""
from pathlib import Path
import plistlib, subprocess, tarfile, tempfile, xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parent.parent
folder=ROOT/'dist'
for kind in ['App','Drivers']:
    package=max(folder.glob(f'Audiomeeter-{kind}-*.pkg'),key=lambda p:p.stat().st_mtime)
    with tempfile.TemporaryDirectory(dir=ROOT/'.build',prefix='package-check-') as temp:
        expanded=Path(temp)/'expanded'
        subprocess.run(['pkgutil','--expand-full',str(package),str(expanded)],check=True)
        distribution=ET.parse(expanded/'Distribution').getroot()
        assert distribution.find('options').get('hostArchitectures')=='arm64'
        assert distribution.find('.//os-version').get('min')=='14.0'
        component=expanded/f'{kind}.pkg'; payload=component/'Payload'
        assert (component/'Scripts/preinstall').is_file()
        if kind=='App':
            app=payload/'Applications/Audiomeeter.app'
            info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
            assert info['CFBundleIdentifier']=='local.audiomeeter' and info['AudiomeeterReleaseBuild']
            assert (app/'Contents/Resources/LICENSE.md').is_file()
            assert (app/'Contents/Resources/LICENSES/AGPL-3.0.txt').is_file()
            assert (app/'Contents/Resources/AppIcon.icns').read_bytes()==(ROOT/'Assets/AppIcon.icns').read_bytes()
            subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
        else:
            hal=payload/'Library/Audio/Plug-Ins/HAL'
            names=['Audiomeeter','AudiomeeterAUX','AudiomeeterB1','AudiomeeterB2']
            assert sorted(p.name for p in hal.iterdir())==[name+'.driver' for name in names]
            factories=set()
            for name,suffix,display in zip(names,['vaio','aux','b1','b2'],['Audiomeeter VAIO','Audiomeeter AUX','Audiomeeter B1','Audiomeeter B2']):
                driver=hal/(name+'.driver'); info=plistlib.loads((driver/'Contents/Info.plist').read_bytes())
                assert info['CFBundleIdentifier']==f'local.audiomeeter.driver.{suffix}'
                assert info['CFBundleName']==display
                factory=next(iter(info['CFPlugInFactories'])); assert factory not in factories; factories.add(factory)
                binary=driver/'Contents/MacOS'/name
                assert subprocess.check_output(['lipo','-archs',str(binary)],text=True).strip()=='arm64'
                assert display.encode() in binary.read_bytes() and (name+'_UID').encode() in binary.read_bytes()
                assert (driver/'Contents/Resources/LICENSE.txt').is_file() and (driver/'Contents/Resources/NOTICE.md').is_file()
                subprocess.run(['codesign','--verify','--strict',str(driver)],check=True)
            assert (component/'Scripts/postinstall').is_file()
        print('Package verified:',package.name)
archive=max(folder.glob('Audiomeeter-Source-*.tar.gz'),key=lambda p:p.stat().st_mtime)
with tarfile.open(archive) as source:
    members=source.getmembers(); names={m.name for m in members}; prefix='Audiomeeter-source/'
    for required in ['Sources/main.swift','Drivers/BlackHoleCore.c','LICENSE.md','Packaging/Drivers/scripts/postinstall','.build/dependencies/JUCE/modules/juce_core/juce_core.cpp','.build/dependencies/JUCE/.audiomeeter-source-revision']:
        assert prefix+required in names,required
    assert all(m.uid==0 and m.gid==0 and not m.uname and not m.gname for m in members)
    for name in names:
        parts=Path(name).parts
        assert '.git' not in parts and 'dist' not in parts and 'private-icon' not in parts,name
        assert not any(p.endswith(('.app','.driver')) for p in parts),name
    print('Source verified:',len(members),'files; no Git metadata or compiled bundles')
