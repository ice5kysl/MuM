#!/bin/bash
# measure-ttfr.sh — TTFR 判定数据的可复现测量（口径见 docs/metrics.md）
#
#   TTFR-冷开：双击语义（app 未运行，open 带文件）→「渐进：首屏已写入」
#   TTFR-热开：app 已运行后 open 文件 → readText 到 渐进首屏
#
# 用法：scripts/measure-ttfr.sh [大文件MB数，默认 1] [sha/tag，默认 HEAD]
# 依赖：scripts/build-app.sh、scripts/make-bench-fixture.py
# 规范（COLLABORATION）：判定性测量一律在隔离 worktree 跑 —— 与 accept.sh 同原则
#
# 环境说明（为什么这么绕）：
# - 直接跑 .build/*/MuM 没有 bundle id，读的是另一个 defaults 域，文件打不开
# - 必须经 launchd 的 open 启动（Finder 双击同款路径）
# - 测量写 ai.jiker.mum 用户域 —— 全程 export/import 备份还原，结束不留 /tmp 产物
# - 构建后第一开有 LaunchServices 注册开销，先做一次不计入的预热
set -euo pipefail

# 判定数据只认安静机器：负载高时 SwiftPM/runner/别的 agent 都会污染计时。
# 强制跑：FORCE=1 scripts/measure-ttfr.sh（数字只能当诊断用，不能进判定）
LOAD=$(sysctl -n vm.loadavg | awk '{print int($2)}')
if [ "$LOAD" -gt 4 ] && [ "${FORCE:-0}" != "1" ]; then
  echo "✗ 负载 $LOAD > 4（CI runner / 其他构建会污染计时）。安静后再跑，或 FORCE=1 拿诊断数字" >&2
  exit 3
fi

MB="${1:-1}"
REF="${2:-HEAD}"
SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 判定测量在隔离 worktree 里做：共享树随时有别人的构建/未提交改动，
# 数字必须不受污染；worktree 从指定 ref 新建，量的是明确的提交。
WT=$(mktemp -d /tmp/mum-measure.XXXXXX)
rmdir "$WT"
# 幂等自清理：上次被 SIGKILL 的残留 worktree 先拆掉，不依赖人记得（trap 可能没机会跑）
for stale in $(git -C "$SRC_ROOT" worktree list --porcelain | awk '/^worktree \/tmp\/mum-measure\./ {print $2}'); do
  git -C "$SRC_ROOT" worktree remove --force "$stale" 2>/dev/null || true
done
git -C "$SRC_ROOT" worktree add --detach "$WT" "$REF" >/dev/null 2>&1
ROOT="$WT"
APP="$ROOT/dist/MuM.app"
DOMAIN=ai.jiker.mum
LOG=$(mktemp /tmp/mum-ttfr.XXXXXX)
FIX=$(mktemp /tmp/mum-fix.XXXXXX.md)
COMMIT=$(git -C "$ROOT" rev-parse --short HEAD)

# pipefail 下 grep 无匹配会杀死管道，统一兜底
mark() { grep "$1" "$LOG" | tail -1 | awk '{print $2}' || true; }

cleanup() {
  pkill -f "$WT" 2>/dev/null || true
  launchctl unsetenv MUM_LAUNCH_TIMING 2>/dev/null || true
  if [ -f "$LOG.bak" ]; then defaults import "$DOMAIN" "$LOG.bak"; rm -f "$LOG.bak"; fi
  rm -f "$LOG" "$FIX"
  # LaunchServices 注册同样是用完要收的：残留注册会让后续 open 按名/按 id 路由到
  # 幽灵副本，污染别人和自己的后续测量（E-1 事故的根因之一）
  LSREG='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
  "$LSREG" -u "$WT/dist/MuM.app" 2>/dev/null || true
  git -C "$SRC_ROOT" worktree remove --force "$WT" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> 隔离 worktree @ ${COMMIT}（共享树不受影响）"
echo "==> 构建（全新 .build，约 1-2 分钟）"
"$ROOT/scripts/build-app.sh" debug >/dev/null
python3 "$ROOT/scripts/make-bench-fixture.py" "$MB" "$FIX" >/dev/null
defaults export "$DOMAIN" "$LOG.bak"

launchctl setenv MUM_LAUNCH_TIMING 1

echo "==> 预热（构建后首开，LaunchServices 注册开销，不计入）"
: > "$LOG"
open -a "$APP" --stderr "$LOG" "$FIX"; sleep 5; pkill -f "$WT"; sleep 1

echo "==> 冷开 ×3"
RS=""
for i in 1 2 3; do
  : > "$LOG"
  open -a "$APP" --stderr "$LOG" "$FIX"
  sleep 8; pkill -f "$WT"; sleep 1
  r=$(mark '渐进：首屏已写入')
  echo "冷开 run$i: 窗口 $(mark 'showWindow 返回')ms  首屏R ${r}ms"
  RS="$RS $r"
done
# 判定按区间不按单点（dsh 2026-09-18 要求）：给出中位数与标准差
python3 - $RS <<'PYEOF'
import statistics, sys
xs = [float(x) for x in sys.argv[1:] if x]
if len(xs) >= 2:
    print(f"冷开统计: 中位 {statistics.median(xs):.1f}ms  σ {statistics.stdev(xs):.1f}ms  区间 [{min(xs):.0f}, {max(xs):.0f}]ms  (n={len(xs)})")
PYEOF

echo "==> 热开 ×1（app 已运行后 open 另一文件）"
FIX2="${FIX%.md}-2.md"; cp "$FIX" "$FIX2"   # 大文件副本：空开恢复的是原文件，开副本才走完整 open 链
: > "$LOG"
open -a "$APP" --stderr "$LOG"          # 先空开（会恢复上次文件）
sleep 3
: > "$LOG"
open -a "$APP" "$FIX2"; sleep 8; pkill -f "$WT"; sleep 1
rt=$(mark 'readText 完成'); r=$(mark '渐进：首屏已写入')
if [ -n "$rt" ] && [ -n "$r" ]; then
  echo "热开: open链 ≈$(echo "$r - $rt" | bc)ms （readText ${rt}ms → R ${r}ms）"
else
  echo "热开: 打点未齐（readText=${rt:-无} R=${r:-无}）"
fi
rm -f "$FIX2"
echo "==> 完成（用户域已还原，/tmp 已清）"
