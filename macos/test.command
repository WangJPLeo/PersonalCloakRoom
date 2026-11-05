#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
compiler_bin="$(dirname "$(xcrun --find swiftc)")"
python3 scripts/prepare-toolchain.py "$compiler_bin"
compiler_flags=()
if [[ -f "$PWD/.build/toolchain/overlay.json" ]]; then
    compiler_flags=(-vfsoverlay "$PWD/.build/toolchain/overlay.json")
fi
swiftc -parse-as-library -swift-version 5 "${compiler_flags[@]}" \
    Sources/CloakCapture/Service.swift Sources/CloakCapture/Images.swift Sources/CloakCapture/CaptureFailure.swift \
    Sources/CloakCapture/GarmentCatalog.swift Sources/CloakCapture/HistoryStore.swift \
    Tests/ServiceTests.swift -o .build/contract-tests
.build/contract-tests
python3 Tests/package_config_test.py
python3 Tests/publish_app_test.py
python3 Tests/package_gallery_test.py
