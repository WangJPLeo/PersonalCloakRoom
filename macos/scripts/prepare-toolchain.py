"""Prepare workspace-only overlays for partially upgraded Apple Command Line Tools."""
from pathlib import Path
import json
import shutil
import sys

toolchain = Path(sys.argv[1]).parent
output = Path(__file__).resolve().parents[1] / '.build' / 'toolchain'
output.mkdir(parents=True, exist_ok=True)
manifest = toolchain / 'lib/swift/pm/ManifestAPI'
interfaces = manifest / 'PackageDescription.swiftmodule'
needs_manifest = False
for public in interfaces.glob('*.swiftinterface'):
    if '.private.' in public.name:
        continue
    private = public.with_name(public.name.replace('.swiftinterface', '.private.swiftinterface'))
    if private.exists() and public.read_text().splitlines()[1] != private.read_text().splitlines()[1]:
        needs_manifest = True

marker = output / 'manifest-overlay-required'
if needs_manifest:
    for name in ['ManifestAPI', 'PluginAPI']:
        source = toolchain / 'lib/swift/pm' / name
        if source.exists():
            shutil.copytree(source, output / 'SwiftPMLibs' / name, dirs_exist_ok=True)
            for private in (output / 'SwiftPMLibs' / name).rglob('*.private.swiftinterface'):
                private.unlink()
    marker.touch()
elif marker.exists():
    marker.unlink()

legacy = toolchain / 'include/swift/module.modulemap'
current = toolchain / 'include/swift/bridging.modulemap'
overlay = output / 'overlay.json'
if all(path.exists() and 'module SwiftBridging' in path.read_text() for path in [legacy, current]):
    empty = output / 'empty.modulemap'
    empty.write_text('// Legacy duplicate module hidden by a workspace-only overlay.\n')
    overlay.write_text(json.dumps({'version': 0, 'roots': [
        {'type': 'file', 'name': str(legacy), 'external-contents': str(empty)}
    ]}))
elif overlay.exists():
    overlay.unlink()
