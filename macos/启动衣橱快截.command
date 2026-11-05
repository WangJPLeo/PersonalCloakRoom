#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
if [[ ! -d "dist/衣橱快截.app" ]]; then
    ./build.command
fi
open "dist/衣橱快截.app" --args --show-studio
