#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
compiler_bin="$(dirname "$(xcrun --find swiftc)")"
python3 scripts/prepare-toolchain.py "$compiler_bin"
local_tools="$PWD/.build/toolchain"
if [[ -f "$local_tools/manifest-overlay-required" ]]; then
    export SWIFTPM_CUSTOM_LIBS_DIR="$local_tools/SwiftPMLibs"
fi
toolchain_flags=()
if [[ -f "$local_tools/overlay.json" ]]; then
    toolchain_flags=(-Xswiftc -vfsoverlay -Xswiftc "$local_tools/overlay.json")
fi
exec swift "$@" "${toolchain_flags[@]}"
