#!/usr/bin/env bash
#
# 在**干净检出**上跑验收。
#
#   ./scripts/accept.sh              # 验收当前 main
#   ./scripts/accept.sh v0.3.0       # 验收某个 tag
#   ./scripts/accept.sh <sha>
#
# 为什么必须有这个脚本：三个 agent 共用一个工作目录，任何时刻树里都可能有
# 别人未提交的工作。**在那种树上跑验收，结果不可信** —— 而且你可能在验收
# 根本没打算发布的东西（真实发生过）。
#
# worktree 是同一仓库的另一个检出：共用对象库，但有自己的工作目录和 HEAD。
# 所以既能拿到确切的提交，又完全不碰任何人的工作区。
#
# 用完自动清理（见 docs/collaboration.md 的收尾规范）。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF="${1:-main}"
# ⚠️ worktree 必须建在**仓库之外**。
#
# 早先我把它建在 $ROOT/.build/accept-$$ —— 那是错的，有三个危害，第三个是硬伤：
#   1. 嵌套混乱：worktree 里再有一个 .build/
#   2. 遍历类工具（find / git status / 各种扫描）会钻进去
#   3. **`rm -rf .build` 会连带删掉正在用的 worktree**，而 git 里还留着注册记录，
#      之后 `worktree list` 出现幽灵条目
#
# 用 $TMPDIR：在仓库外、可写、且系统会回收。
WT="${TMPDIR:-/tmp}/mum-accept-$$"

cleanup() {
    git -C "$ROOT" worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"
    git -C "$ROOT" worktree prune 2>/dev/null || true
}
trap cleanup EXIT

# 先清掉历史遗留：上一次被 SIGKILL 掉、trap 没跑成的残留。
# 不先 prune 的话，同名路径复用会失败。
git -C "$ROOT" worktree prune 2>/dev/null || true

echo "═══ 干净检出 $REF ═══"
git -C "$ROOT" worktree add -q --detach "$WT" "$REF"
COMMIT="$(git -C "$WT" log --oneline -1)"
echo "  $COMMIT"
[ -z "$(git -C "$WT" status --porcelain)" ] && echo "  工作区干净 ✅" || { echo "  ❌ 检出后不干净，中止"; exit 1; }

# 复用主仓库已拉取的依赖：worktree 是全新目录，没有 .build/checkouts，
# 不这么做 SwiftPM 会重新联网拉 swift-markdown（慢，且可能失败）。
mkdir -p "$WT/.build"
for d in checkouts repositories artifacts; do
    [ -d "$ROOT/.build/$d" ] && cp -R "$ROOT/.build/$d" "$WT/.build/" 2>/dev/null || true
done

# 构建缓存重定向到本地（受限沙箱里 $TMPDIR 下的 clang 模块缓存不可写）
export CLANG_MODULE_CACHE_PATH="$WT/.build/modulecache"
export SWIFT_MODULE_CACHE_PATH="$WT/.build/modulecache"

echo
echo "═══ 构建 ═══"
(cd "$WT" && swift build -c release --disable-sandbox 2>&1 | tail -1)

echo
echo "═══ 渲染自检（24 项断言）═══"
"$WT/.build/release/MuM" --selftest 2>&1 | tail -1

echo
echo "═══ 单元测试 ═══"
# 加 `|| true`：swift test 在冷 worktree 里首次构建测试目标可能很慢（实测 >10min），
# 不能让它把整个验收脚本拖死。这一步失败要显式报出来，但继续往下走完。
if ! (cd "$WT" && swift test --disable-sandbox 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1); then
    echo "  ⚠️ 测试未出结果（超时或失败）—— 需要单独看"
fi

echo
echo "═══ 打包（含版本号一致性）═══"
(cd "$WT" && ./scripts/build-app.sh release 2>&1 | grep -E "版本|完成" | tail -2)

echo
echo "─── 判定性测量请另外做 ───"
echo "TTFR 等指标要用 bundle 内的二进制："
echo "  $WT/dist/MuM.app/Contents/MacOS/MuM"
echo "直接跑 .build/release/MuM 没有 bundle id，读的是另一个 defaults 域 —— 会得到假结果。"
echo
echo "（本脚本只验可自动化的部分。空状态、popover、颜色这些必须真实点击/截图。）"
