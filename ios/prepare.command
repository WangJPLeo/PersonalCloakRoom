#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .generated
compiler_bin="$(dirname "$(xcrun --find swiftc)")"
python3 ../macos/scripts/prepare-toolchain.py "$compiler_bin"
icon_flags=()
if [[ -f "$PWD/../macos/.build/toolchain/overlay.json" ]]; then
    icon_flags=(-vfsoverlay "$PWD/../macos/.build/toolchain/overlay.json")
fi
swiftc "${icon_flags[@]}" ../macos/scripts/icon.swift -o .generated/icon-tool
.generated/icon-tool .generated/AppIcon.icns
python3 scripts/prepare.py
swiftc "${icon_flags[@]}" scripts/opaque_icon.swift -o .generated/opaque-icon-tool
.generated/opaque-icon-tool .generated/Assets.xcassets/AppIcon.appiconset/icon1024.png
