#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build
compiler_bin="$(dirname "$(xcrun --find swiftc)")"
python3 ../macos/scripts/prepare-toolchain.py "$compiler_bin"
compiler_flags=()
if [[ -f "$PWD/../macos/.build/toolchain/overlay.json" ]]; then
    compiler_flags=(-vfsoverlay "$PWD/../macos/.build/toolchain/overlay.json")
fi
# Portable production code runs against the installed macOS SDK. UIKit still requires an iOS SDK.
swiftc -parse-as-library -swift-version 5 "${compiler_flags[@]}" \
    Shared/MobileStorage.swift Shared/MobileCredentials.swift Shared/ShareImageLoader.swift \
    ../macos/Sources/CloakCapture/Service.swift ../macos/Sources/CloakCapture/HistoryStore.swift \
    Tests/MobileStorageTests.swift -o .build/mobile-storage-tests
.build/mobile-storage-tests
swiftc -frontend -parse "${compiler_flags[@]}" App/*.swift Shared/*.swift ShareExtension/*.swift
python3 Tests/project_test.py
print "共享逻辑与工程结构检查通过。UIKit、分享扩展签名和真机操作仍需完整 Xcode 验证。"
