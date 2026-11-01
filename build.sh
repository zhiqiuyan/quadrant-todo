#!/usr/bin/env bash
# 命令行构建脚本：不打开 IDE 直接产出 HAP。
# 用法：
#   ./build.sh            # debug 构建（未签名）
#   ./build.sh release    # release 构建（未签名，需另外配置签名才能上真机）
set -euo pipefail

DEVECO_HOME="${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}"
MODE="${1:-debug}"

export DEVECO_SDK_HOME="$DEVECO_HOME/sdk"
export NODE_HOME="$DEVECO_HOME/tools/node"
export JAVA_HOME="$DEVECO_HOME/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:$NODE_HOME/bin:$PATH"

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

if [ ! -d "$DEVECO_HOME" ]; then
  echo "未找到 DevEco Studio：$DEVECO_HOME" >&2
  echo "如安装在别处，请指定 DEVECO_HOME=/path/to/DevEco-Studio.app/Contents" >&2
  exit 1
fi

"$DEVECO_HOME/tools/hvigor/bin/hvigorw" \
  assembleHap \
  --mode module \
  -p product=default \
  -p buildMode="$MODE" \
  --no-daemon

echo "---- 产物 ----"
find entry/build -name "*.hap" -exec ls -lh {} \;
