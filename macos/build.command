#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

./scripts/swift.sh build -c release -j 2
package_stage="$(mktemp -d "$PWD/.build/package.XXXXXX")"
trap 'rm -rf -- "$package_stage"' EXIT
app_dir="$package_stage/衣橱快截.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
bin_dir="$(./scripts/swift.sh build -c release --show-bin-path)"
cp "$bin_dir/CloakCapture" "$app_dir/Contents/MacOS/CloakCapture"
cp Info.plist "$app_dir/Contents/Info.plist"
if [[ -f Config.local.plist ]]; then
    cp Config.local.plist "$app_dir/Contents/Resources/Config.local.plist"
else
    cp Config.example.plist "$app_dir/Contents/Resources/Config.local.plist"
fi
chmod 600 "$app_dir/Contents/Resources/Config.local.plist"

# AppKit needs an ATS exception for a user-authorized remote HTTP origin.
# The network layer independently enforces that exact origin and refuses redirects.
python3 scripts/package_config.py "$app_dir"
python3 scripts/package_gallery.py "$app_dir/Contents/Resources/Gallery"

icon_flags=()
if [[ -f "$PWD/.build/toolchain/overlay.json" ]]; then
    icon_flags=(-vfsoverlay "$PWD/.build/toolchain/overlay.json")
fi
swiftc "${icon_flags[@]}" scripts/icon.swift -o .build/icon-tool
.build/icon-tool "$app_dir/Contents/Resources/AppIcon.icns"
signing_identity="${CLOAK_CODESIGN_IDENTITY:--}"
codesign --force --sign "$signing_identity" --identifier app.personalcloakroom.capture "$app_dir"
python3 scripts/publish_app.py "$app_dir"
print "构建完成：dist/衣橱快截.app"
