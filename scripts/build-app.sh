#!/usr/bin/env bash
#
# 把 SwiftPM 产出的可执行文件组装成 MuM.app。
#
# 为什么不用 Xcode 工程：整个应用没有任何 Xcode 专有资源（storyboard、xib、asset
# catalog），一个 Info.plist 加一个二进制就是完整的 .app。用纯 SwiftPM + 这个脚本，
# 构建链路只剩一条 `swift build`，没有 .xcodeproj 需要人工维护、也不会产生
# 合并冲突。
#
# 用法：
#   ./scripts/build-app.sh            # release 构建
#   ./scripts/build-app.sh debug      # debug 构建
#   ./scripts/run.sh                  # 构建并启动

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="$ROOT/dist/MuM.app"

# 沙箱内构建所需：把 SwiftPM / clang 的缓存重定向到工作区
# shellcheck disable=SC1091
source "$ROOT/.mumenv"

echo "==> 生成应用图标"
mkdir -p "$ROOT/.build/icon"
if ! swift "$ROOT/scripts/make-icon.swift" "$ROOT/.build/icon" >/dev/null 2>&1; then
  echo "    (图标生成失败，继续用系统默认图标)"
fi
if [ -d "$ROOT/.build/icon/AppIcon.iconset" ]; then
  iconutil -c icns "$ROOT/.build/icon/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns" 2>/dev/null || true
fi

echo "==> 编译（${CONFIG}）"
swift build -c "$CONFIG" --disable-sandbox

BIN_DIR="$(swift build -c "$CONFIG" --disable-sandbox --show-bin-path)"
BIN="$BIN_DIR/MuM"

if [ ! -x "$BIN" ]; then
  echo "找不到可执行文件：$BIN" >&2
  exit 1
fi

echo "==> 组装 ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MuM"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# 版本号的唯一来源是仓库根目录的 VERSION（SemVer）。
# 构建时写进 Info.plist —— 只维护一处，脚本和 README 都从它读。
VERSION=$(tr -d '[:space:]' < "$ROOT/VERSION")
if [ -z "$VERSION" ]; then
    echo "错误：VERSION 文件为空" >&2
    exit 1
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
# CFBundleVersion 必须是单调递增的整数字符串（Sparkle / App Store 用），
# 由 SemVer 折算：0.1.2 → 102，1.4.0 → 10400。
BUILD_NUMBER=$(echo "$VERSION" | awk -F. '{printf "%d", $1*10000 + $2*100 + $3}')
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
echo "    版本 $VERSION (build $BUILD_NUMBER)"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# 未签名的 app 在 Apple Silicon 上无法启动，ad-hoc 签名即可满足本机运行
echo "==> ad-hoc 签名"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || echo "    (签名失败，可能无法启动)"

SIZE="$(du -sh "$APP" | cut -f1)"
echo "==> 完成：${APP}（${SIZE}）"
