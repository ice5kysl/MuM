#!/bin/bash
# launch-stats.sh — PH 发布日聚合盯盘（只读）：PH 票数/排名 + GitHub star/下载/仓库流量。
#
# 用法：
#   scripts/launch-stats.sh             # 打印一次快照，并追加一行到 .launch-stats.csv
#   scripts/launch-stats.sh --no-log    # 只打印不写文件
#
# CSV 列：time, ph_votes, ph_comments, ph_rank, gh_stars, gh_dl_080, gh_dl_total, gh_views14d, gh_uniques14d
# 凭据：PH 从 .mumenv.local 读；GitHub 走 gh CLI 的登录态。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/.launch-stats.csv"
SLUG="mum-multi-project-markdown"
# shellcheck source=/dev/null
source "$ROOT/.mumenv.local"

TOKEN=$(curl -s -X POST https://api.producthunt.com/v2/oauth/token \
  -d "client_id=$PH_CLIENT_ID&client_secret=$PH_CLIENT_SECRET&grant_type=client_credentials" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")

PH=$(curl -s https://api.producthunt.com/v2/api/graphql \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"query":"{ post(slug:\"'$SLUG'\") { votesCount commentsCount dailyRank } }"}' \
  | python3 -c "
import json,sys
p=(json.load(sys.stdin).get('data') or {}).get('post') or {}
print(p.get('votesCount',0), p.get('commentsCount',0), p.get('dailyRank') or 0)")

GH=$(gh api repos/ice5kysl/MuM --jq '.stargazers_count')
DL=$(gh api repos/ice5kysl/MuM/releases --jq '[.[].assets[].download_count] | add // 0')
DL080=$(gh api repos/ice5kysl/MuM/releases --jq '.[] | select(.tag_name=="v0.8.0") | [.assets[].download_count] | add // 0' | head -1)
TRAFFIC=$(gh api repos/ice5kysl/MuM/traffic/views --jq '.count, .uniques' | tr '\n' ' ')

read -r VOTES COMMENTS RANK <<< "$PH"
read -r VIEWS UNIQUES <<< "$TRAFFIC"
NOW=$(date '+%Y-%m-%d %H:%M')

printf '%s | PH 票 %s 评论 %s 排名 %s | star %s | 下载 v0.8.0=%s 全部=%s | 仓库 14d 访问 %s/%s 人\n' \
  "$NOW" "$VOTES" "$COMMENTS" "${RANK:-—}" "$GH" "${DL080:-0}" "$DL" "$VIEWS" "$UNIQUES"

if [ "${1:-}" != "--no-log" ]; then
  [ -f "$LOG" ] || echo "time,ph_votes,ph_comments,ph_rank,gh_stars,gh_dl_080,gh_dl_total,gh_views14d,gh_uniques14d" > "$LOG"
  echo "$NOW,$VOTES,$COMMENTS,$RANK,$GH,${DL080:-0},$DL,$VIEWS,$UNIQUES" >> "$LOG"
fi
