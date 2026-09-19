#!/usr/bin/env bash
# 文档一致性检查。每次发版前跑。
#
# 为什么需要它：docs/ 在两天内烂过三次 —— status 停在 v0.4.1、roadmap 停在 0.2.0、
# vision 写着 2.8 MB 而实际 3.4 MB。**共同点都是"人忘了改"**。
# 能自动查的就不该靠人记得。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fail=0
say() { printf '  %-34s %s\n' "$1" "$2"; }

V=$(cat VERSION | tr -d '\n')
PLIST=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/MuM.app/Contents/Info.plist 2>/dev/null || echo '未构建')
TAG=$(git tag -l 'v*' | tail -1)
say "版本三处一致" "$([ "$V" = "$PLIST" ] && [ "v$V" = "$TAG" ] && echo "✅ $V / $PLIST / $TAG" || { fail=1; echo "❌ $V / $PLIST / $TAG"; })"

N=$(ls -1 *.md 2>/dev/null | wc -l | tr -d ' ')
say "根目录 *.md ≤2" "$([ "$N" -le 2 ] && echo "✅ $N" || { fail=1; echo "❌ $N 个"; })"

L=$(wc -l < README.md | tr -d ' ')
say "README ≤200 行" "$([ "$L" -le 200 ] && echo "✅ $L" || { fail=1; echo "❌ $L 行"; })"

B=$(python3 - <<'PY'
import pathlib, re
bad=[]
for f in [pathlib.Path("README.md")]+list(pathlib.Path("docs").rglob("*.md")):
    for m in re.finditer(r"\]\(([^)#]+\.(md|png|svg))\)", f.read_text()):
        t=m.group(1)
        if t.startswith(("http","/")): continue
        if not (f.parent/t).resolve().exists(): bad.append(f"{f}→{t}")
print(len(bad))
PY
)
say "文档无断链" "$([ "$B" = "0" ] && echo "✅ 0" || { fail=1; echo "❌ $B 处"; })"

S=$(grep -rl "fast, native Markdown engine\|multi-project Markdown reader" README.md docs/vision.md docs/roadmap.md docs/metrics.md docs/status.md site/ 2>/dev/null | wc -l | tr -d ' ')
say "无旧定位句（在外文件）" "$([ "$S" = "0" ] && echo "✅ 0" || { fail=1; echo "❌ $S 处"; })"

# status.md 的「最后更新」不能比最新 tag 落后太多 —— 只能提醒，无法自动判
say "status.md 最新版本号" "$(grep -oE 'v0\.[0-9]+\.[0-9]+' docs/status.md | head -1)"

echo
[ "$fail" = "0" ] && echo "文档检查：全过 ✅" || echo "文档检查：有不过的 ❌"
exit $fail
