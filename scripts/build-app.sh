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
#   ./scripts/build-app.sh            # release 构建（ad-hoc 签名，本机用）
#   ./scripts/build-app.sh debug      # debug 构建
#   ./scripts/build-app.sh release --sign        # 发版构建：Developer ID 签名 + 公证 + 装订
#   ./scripts/build-app.sh release --sign --dmg  # 再出一个装订过的 DMG
#   ./scripts/run.sh                  # 构建并启动
#
# --sign 的身份与公证凭据从 .mumenv.local 读（不入库，见 .mumenv.local.example）；
# 没配就带清楚的话失败，不会静默产出未签名的包。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="release"
SIGN=0
DMG=0
for arg in "$@"; do
  case "$arg" in
    debug|release) CONFIG="$arg" ;;
    --sign) SIGN=1 ;;
    --dmg) DMG=1 ;;
    *) echo "未知参数：${arg}（用法：build-app.sh [debug|release] [--sign] [--dmg]）" >&2; exit 2 ;;
  esac
done
APP="$ROOT/dist/MuM.app"

# 沙箱内构建所需：把 SwiftPM / clang 的缓存重定向到工作区
# shellcheck disable=SC1091
source "$ROOT/.mumenv"

echo "==> 生成应用图标"
mkdir -p "$ROOT/.build/icon"
# 图标源是 ice 手绘版 logo（深色版进 Dock）；make-icon.swift 是旧的代码绘制版，已退役
if ! swift "$ROOT/scripts/make-icon-from-logo.swift" "$ROOT/logo/MuM_logo_d.png" "$ROOT/.build/icon" >/dev/null 2>&1; then
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

# `mum` 命令行入口：本体随 bundle 发布，用户软链到 PATH 即可（见 README）。
# 放在 Resources 而不是 MacOS：macOS 默认大小写不敏感，`MacOS/mum` 和主二进制
# `MacOS/MuM` 是同一个文件 —— 拷过去会把二进制覆盖掉（踩过，勿移）。
cp "$ROOT/scripts/mum" "$APP/Contents/Resources/mum"
chmod +x "$APP/Contents/Resources/mum"

if [ "$SIGN" = "1" ]; then
  # 发版签名：身份/凭据在本机配置里（gitignored），先载进来
  if [ -f "$ROOT/.mumenv.local" ]; then
    # shellcheck disable=SC1091
    source "$ROOT/.mumenv.local"
  fi
  DMG_FLAG=""
  [ "$DMG" = "1" ] && DMG_FLAG="--dmg"
  # sign-release.sh 里对缺配置是带清楚的话直接失败（:? 而不是静默降级）
  "$ROOT/scripts/sign-release.sh" "$APP" $DMG_FLAG
else
  # 未签名的 app 在 Apple Silicon 上无法启动，ad-hoc 签名即可满足本机运行
  echo "==> ad-hoc 签名（本机运行用；出发版包：$0 $CONFIG --sign，身份配置见 .mumenv.local.example）"
  codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || echo "    (签名失败，可能无法启动)"

  SIZE="$(du -sh "$APP" | cut -f1)"
  echo "==> 完成：${APP}（${SIZE}）"
fi
