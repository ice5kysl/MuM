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
if [ "$V" = "$PLIST" ] && [ "v$V" = "$TAG" ]; then say "版本三处一致" "✅ $V / $PLIST / $TAG"; else say "版本三处一致" "❌ $V / $PLIST / $TAG"; fail=1; fi

N=$(ls -1 *.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$N" -le 3 ]; then say "根目录 *.md ≤3" "✅ $N"; else say "根目录 *.md ≤3" "❌ $N 个"; fail=1; fi

for R in README.md README_EN.md; do
  [ -f "$R" ] || continue
  L=$(wc -l < "$R" | tr -d ' ')
  if [ "$L" -le 200 ]; then say "$R ≤200 行" "✅ $L"; else say "$R ≤200 行" "❌ $L 行"; fail=1; fi
done

B=$(python3 - <<'PY'
import pathlib, re
bad=[]
for f in [pathlib.Path("README.md"), pathlib.Path("README_EN.md")]+list(pathlib.Path("docs").rglob("*.md")):
    for m in re.finditer(r"\]\(([^)#]+\.(md|png|svg))\)", f.read_text()):
        t=m.group(1)
        if t.startswith(("http","/")): continue
        if not (f.parent/t).resolve().exists(): bad.append(f"{f}→{t}")
print(len(bad))
PY
)
if [ "$B" = "0" ]; then say "文档无断链" "✅ 0"; else say "文档无断链" "❌ $B 处"; fail=1; fi

S=$(grep -rl "fast, native Markdown engine\|multi-project Markdown reader" README.md docs/vision.md docs/roadmap.md docs/metrics.md docs/status.md site/ 2>/dev/null | wc -l | tr -d ' ')
if [ "$S" = "0" ]; then say "无旧定位句（在外文件）" "✅ 0"; else say "无旧定位句（在外文件）" "❌ $S 处"; fail=1; fi

# status.md 的「最后更新」不能比最新 tag 落后太多 —— 只能提醒，无法自动判
# 发版时最容易漏的一步：落地页的下载链接与版本号
SITE=$(grep -ohE 'releases/download/v[0-9.]+' site/index.html 2>/dev/null | head -1 | grep -oE 'v[0-9.]+')
if [ "v$V" = "$SITE" ]; then say "落地页下载链接跟上版本" "✅ $SITE"; else say "落地页下载链接跟上版本" "❌ 页面是 ${SITE}，版本是 v$V"; fail=1; fi

say "roadmap 当前版本" "$(grep -oE "v0\\.[0-9]+\\.[0-9]+" docs/roadmap.md | head -1)"

echo
[ "$fail" = "0" ] && echo "文档检查：全过 ✅" || echo "文档检查：有不过的 ❌"
exit $fail
