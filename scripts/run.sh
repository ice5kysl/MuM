#!/usr/bin/env bash
#
# 构建并启动 MuM。
#
# 用 `open` 而不是直接跑二进制：只有走 LaunchServices 启动，应用才会拿到正确的
# 前台身份和 Info.plist 里声明的文档类型（否则菜单栏和 Dock 行为会不对）。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/build-app.sh" "${1:-release}"

echo "==> 启动 MuM"
# 先杀掉旧实例，避免叠开一堆窗口
pkill -x MuM 2>/dev/null || true
sleep 0.3
open "$ROOT/dist/MuM.app"

echo "已启动。"
