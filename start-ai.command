#!/bin/zsh
cd -- "${0:A:h}" || exit 1
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/local/go/bin:$PATH"
if ! command -v node >/dev/null 2>&1 || ! command -v go >/dev/null 2>&1; then
  print 'AI 后端启动需要本机安装 Node.js 与 Go。'
  read '?按回车键退出。'
  exit 1
fi
node --env-file=backend/.env scripts/start-ai.mjs
status_code=$?
if (( status_code != 0 )); then
  read '?启动未完成，按回车键退出。'
fi
exit "$status_code"
