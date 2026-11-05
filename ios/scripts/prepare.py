from pathlib import Path
import plistlib
import runpy
import struct

root = Path(__file__).resolve().parents[1]
project = root.parent
generated = root / '.generated'
generated.mkdir(exist_ok=True)
local = root / 'Config.local.plist'
if not local.exists():
    source = project / 'macos/Config.local.plist'
    source = source if source.exists() else root / 'Config.example.plist'
    values = plistlib.loads(source.read_bytes())
    local.write_bytes(plistlib.dumps({key: values[key] for key in ['ServiceURL', 'AllowHTTPForService']}))
config = plistlib.loads(local.read_bytes())
if set(config) - {'ServiceURL', 'AllowHTTPForService'}:
    raise ValueError('Config.local.plist accepts only ServiceURL and AllowHTTPForService; credentials belong in the device Keychain')
if not isinstance(config.get('ServiceURL'), str) or not isinstance(config.get('AllowHTTPForService', False), bool):
    raise ValueError('Invalid service configuration types')
(generated / 'Config.local.plist').write_bytes(plistlib.dumps(config))
configure = runpy.run_path(str(project / 'macos/scripts/package_config.py'))['configure_transport']
for folder, output in [('App', 'AppInfo.plist'), ('ShareExtension', 'ShareInfo.plist')]:
    info = plistlib.loads((root / folder / 'Info.plist').read_bytes())
    (generated / output).write_bytes(plistlib.dumps(configure(info, config)))
package = runpy.run_path(str(project / 'macos/scripts/package_gallery.py'))['package_gallery']
count = package(project / 'data.js', project / 'assets', generated / 'Gallery')

# Reuse the existing code-drawn icon. prepare.command then removes the alpha channel for iOS.
icon_data = (generated / 'AppIcon.icns').read_bytes()
offset = 8
png = None
while offset + 8 <= len(icon_data):
    kind, length = struct.unpack('>4sI', icon_data[offset:offset + 8])
    if length < 8:
        raise ValueError('Invalid icon chunk')
    if kind == b'ic10':
        png = icon_data[offset + 8:offset + length]
        break
    offset += length
if not png or not png.startswith(b'\x89PNG\r\n\x1a\n'):
    raise ValueError('Missing 1024px app icon')
icons = generated / 'Assets.xcassets/AppIcon.appiconset'
icons.mkdir(parents=True, exist_ok=True)
(icons / 'icon1024.png').write_bytes(png)
(icons / 'Contents.json').write_text('{"images":[{"filename":"icon1024.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}')
(generated / 'Assets.xcassets/Contents.json').write_text('{"info":{"author":"xcode","version":1}}')
runpy.run_path(str(root / 'scripts/generate_project.py'))['generate'](root)
print(f'iPhone 工程已准备：原生应用、分享扩展、{count} 套离线服装。')
