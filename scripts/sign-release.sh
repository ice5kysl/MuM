#!/usr/bin/env bash
#
# MuM 商店外分发：签名 → 打包 → 公证 → 装订（→ 可选 DMG）。
#
#   ./scripts/sign-release.sh dist/MuM.app           # 签名 + 公证 + 装订
#   ./scripts/sign-release.sh dist/MuM.app --dmg     # 再出一个装订过的 DMG
#   ./scripts/sign-release.sh dist/MuM.app --sign-only   # 只签名验证，不提交公证
#
# 身份与凭据（ice 2026-09-19 决策：公司项目，复用既有资产）：
#   - 证书：公司 Developer ID Application（本机登录钥匙串，含私钥）
#   - 公证：keychain profile `<见 .mumenv.local.example>`（复用已有的 App Store Connect API Key，
#     一次性 `xcrun notarytool store-credentials` 已配置）
# 流程依据：本机签名资产指引（本机实测版）。
#
# MuM 是单二进制（无 Frameworks/插件），直接签 .app 即可，不需要逐个签嵌套项。

set -euo pipefail

APP="${1:?用法：scripts/sign-release.sh <MuM.app> [--dmg|--sign-only]}"
IDENTITY="Developer ID Application: <见 .mumenv.local.example>"
PROFILE="<见 .mumenv.local.example>"

if [ ! -d "$APP" ]; then
  echo "找不到 $APP" >&2
  exit 1
fi

echo "==> 签名（hardened runtime + 时间戳）"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

echo "==> 验证签名"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -2
# 未公证前 spctl 必然 rejected，只确认签名本身有效
# （-dv 的输出走 stderr，不转过来 grep 会空读并以 1 退出，pipefail 直接杀脚本）
codesign -dv "$APP" 2>&1 | grep -E "TeamIdentifier|Signature"

if [ "${2:-}" = "--sign-only" ]; then
  echo "==> --sign-only：到此为止，未提交公证"
  exit 0
fi

echo "==> 打包提交公证"
ZIP="${APP%.app}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "==> 装订（离线也能过 Gatekeeper）"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP"

if [ "${2:-}" = "--dmg" ]; then
  DMG="${APP%.app}.dmg"
  echo "==> 出 DMG：$DMG"
  rm -f "$DMG"
  hdiutil create -volname "MuM" -srcfolder "$APP" -ov -format UDZO "$DMG" | tail -1
  # DMG 是独立容器：.app 的公证票据贴不到它身上，
  # 必须单独签名、单独提交公证、单独装订（实测 stapler Error 65 的教训）
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

echo "==> 完成。$APP 已签名 + 公证 + 装订"
