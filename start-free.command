#!/bin/zsh
cd -- "${0:A:h}" || exit 1
if ! command -v node >/dev/null 2>&1; then
  export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
fi
if ! command -v node >/dev/null 2>&1; then
  print '未找到 Node.js。也可直接用浏览器打开项目中的 index.html 使用免费图库。'
  read '?按回车键退出。'
  exit 1
fi
node scripts/serve-free.mjs
status_code=$?
if (( status_code != 0 )); then
  read '?启动未完成，按回车键退出。'
fi
exit "$status_code"
