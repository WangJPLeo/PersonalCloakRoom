#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
    print -u2 "缺少 iOS SDK：请安装完整 Xcode 并选择它作为开发工具，再运行构建。源码与共享逻辑测试不需要 iOS SDK。"
    exit 1
fi
./prepare.command
mkdir -p dist .build
archive_root="$(mktemp -d "$PWD/.build/archive.XXXXXX")"
trap 'rm -rf -- "$archive_root"' EXIT
xcodebuild -project CloakRoom.xcodeproj -scheme CloakRoom -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData \
    -archivePath "$archive_root/衣橱快截.xcarchive" archive
# Archive only after a successful build. Keep this app's newest archive.
python3 - "$archive_root/衣橱快截.xcarchive" <<'PY'
import pathlib, shutil, sys
source = pathlib.Path(sys.argv[1])
output = pathlib.Path('dist/衣橱快截.xcarchive')
backup = output.with_name('previous.xcarchive')
if output.exists():
    if backup.exists(): shutil.rmtree(backup)
    output.rename(backup)
try:
    source.rename(output)
except BaseException:
    if backup.exists(): backup.rename(output)
    raise
if backup.exists(): shutil.rmtree(backup)
PY
print "已生成最新 iPhone Archive，请在 Xcode Organizer 中选择签名分发或设备安装方式。"
