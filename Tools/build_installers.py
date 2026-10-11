#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Build app and HAL packages locally. Never installs, notarizes or uploads them."""
from pathlib import Path
import argparse, hashlib, json, os, plistlib, shutil, subprocess, tempfile
ROOT = Path(__file__).resolve().parent.parent
DRIVERS = ['Audiomeeter','AudiomeeterAUX','AudiomeeterB1','AudiomeeterB2']
def run(*args, **kwargs):
    subprocess.run([str(x) for x in args],cwd=ROOT,check=True,**kwargs)
def components(payload, destination):
    run('pkgbuild','--analyze','--root',payload,destination)
    values = plistlib.loads(destination.read_bytes())
    for item in values:
        item['BundleIsRelocatable'] = False
        item['BundleOverwriteAction'] = 'upgrade'
    destination.write_bytes(plistlib.dumps(values))
def build(skip_build=False, signed=False):
    if subprocess.check_output(['git','status','--porcelain'],cwd=ROOT).strip():
        raise SystemExit('Commit source changes before building distribution packages.')
    output = ROOT/'dist'; output.mkdir(exist_ok=True)
    app_id = os.environ.get('VM_CODESIGN_IDENTITY','')
    package_id = os.environ.get('VM_INSTALLER_SIGNING_IDENTITY','')
    if signed and (not app_id.startswith('Developer ID Application:') or not package_id.startswith('Developer ID Installer:')):
        raise SystemExit('--signed requires VM_CODESIGN_IDENTITY and VM_INSTALLER_SIGNING_IDENTITY Developer ID identities.')
    if not skip_build:
        env = dict(os.environ,VM_RELEASE_BUILD='1')
        if signed:
            env.update(VM_DISTRIBUTION_SIGN='1',VM_DRIVER_SIGNING_IDENTITY=app_id)
        run('./build_app.sh',env=env); run('./Drivers/build_all_drivers.sh',env=env)
    app = ROOT/'Audiomeeter.app'
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    if not info.get('AudiomeeterReleaseBuild'):
        raise SystemExit('Refusing to package an unmarked build. Build with VM_RELEASE_BUILD=1.')
    version = info['CFBundleShortVersionString']; number = info['CFBundleVersion']
    label = f'{version}-{number}-arm64'+('' if signed else '-LOCAL-UNSIGNED')
    def verify_code(path):
        run('codesign','--verify','--deep','--strict',path)
        if signed:
            result = subprocess.run(['codesign','-dv','--verbose=4',str(path)],capture_output=True,text=True,check=True)
            details = result.stderr
            if 'Authority=Developer ID Application:' not in details or 'runtime' not in details:
                raise SystemExit(f'Refusing non-distribution-signed code: {path}')
    if signed:
        for path in [app, app/'Contents/Helpers/VMPluginWorker.app',app/'Contents/Frameworks/libVMPluginHost.dylib']:
            verify_code(path)
    results = []
    with tempfile.TemporaryDirectory(prefix='Audiomeeter-packages-',dir=ROOT/'.build') as temporary:
        stage = Path(temporary)
        for kind in ['App','Drivers']:
            payload = stage/kind/'payload'; payload.mkdir(parents=True)
            if kind == 'App':
                dest = payload/'Applications/Audiomeeter.app'; dest.parent.mkdir(parents=True)
                shutil.copytree(app,dest,symlinks=True)
                verify_code(dest)
            else:
                for driver in DRIVERS:
                    source = ROOT/f'.build/drivers/{driver}.driver'
                    verify_code(source)
                    dest = payload/f'Library/Audio/Plug-Ins/HAL/{driver}.driver'
                    shutil.copytree(source,dest,symlinks=True)
            config = stage/kind/'components.plist'; components(payload,config)
            component = stage/f'{kind}.pkg'
            run('pkgbuild','--root',payload,'--component-plist',config,'--scripts',ROOT/f'Packaging/{kind}/scripts',
                '--identifier',f'local.audiomeeter.installer.{kind.lower()}', '--version',f'{version}.{number}',
                '--install-location','/','--ownership','recommended',component)
            resources = stage/kind/'resources'; resources.mkdir()
            shutil.copy2(ROOT/'Packaging/Resources/Welcome.txt',resources/'Welcome.txt')
            license_files = ['LICENSE.md','LICENSES/AGPL-3.0.txt','LICENSES/BlackHole-GPL-3.0.txt','THIRD_PARTY_NOTICES.md']
            (resources/'License.txt').write_text('\n\n'.join((ROOT/x).read_text() for x in license_files))
            # Installer cannot relocate the app or HAL bundles; it only targets the live system.
            distribution = stage/kind/'Distribution.xml'
            distribution.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<installer-gui-script minSpecVersion="2">
<title>Audiomeeter {kind}</title><welcome file="Welcome.txt"/><license file="License.txt"/>
<options customize="never" require-scripts="true" hostArchitectures="arm64"/>
<domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
<volume-check><allowed-os-versions><os-version min="14.0"/></allowed-os-versions></volume-check>
<choices-outline><line choice="install"/></choices-outline>
<choice id="install" title="Audiomeeter {kind}"><pkg-ref id="local.audiomeeter.installer.{kind.lower()}"/></choice>
<pkg-ref id="local.audiomeeter.installer.{kind.lower()}" version="{version}.{number}">{kind}.pkg</pkg-ref>
</installer-gui-script>''')
            target = output/f'Audiomeeter-{kind}-{label}.pkg'
            args = ['productbuild','--distribution',distribution,'--package-path',stage,'--resources',resources]
            if signed: args += ['--sign',package_id]
            run(*args,target); results.append(target)
    source = output/f'Audiomeeter-Source-{version}-{number}.tar.gz'
    run('python3',ROOT/'Tools/export_release_source.py',source); results.append(source)
    manifest = {'version':version,'build':number,'architecture':'arm64','signed':signed,'notarized':False,
                'revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in results}}
    (output/f'release-manifest-{label}.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Built local packages and corresponding source. Nothing was installed or uploaded.')
if __name__ == '__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--skip-build',action='store_true'); parser.add_argument('--signed',action='store_true')
    args=parser.parse_args(); build(args.skip_build,args.signed)
