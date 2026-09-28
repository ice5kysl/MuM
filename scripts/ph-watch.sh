#!/bin/bash
# ph-watch.sh — Product Hunt 发布日盯盘（只读）。
#
# 用法：
#   scripts/ph-watch.sh <post-slug>           # 拉一次：票数/排名/最新评论
#   scripts/ph-watch.sh <post-slug> --watch   # 每 120s 刷一次，有变化才打印
#
# 凭据从 .mumenv.local 读（PH_CLIENT_ID / PH_CLIENT_SECRET），不进仓库。
# token 每次启动换一次，--watch 期间复用（PH token 有效期足够长）。

set -euo pipefail

SLUG="${1:?用法: ph-watch.sh <post-slug> [--watch]}"
WATCH="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/.mumenv.local"

GRAPHQL='{ post(slug:"'"$SLUG"'") { name tagline votesCount commentsCount featuredAt dailyRank reviewsRating comments(first:5){ nodes { body user { name } } } } }'

get_token() {
  curl -s -X POST https://api.producthunt.com/v2/oauth/token \
    -d "client_id=$PH_CLIENT_ID&client_secret=$PH_CLIENT_SECRET&grant_type=client_credentials" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])"
}

snapshot() {
  curl -s https://api.producthunt.com/v2/api/graphql \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"query\":$(python3 -c "import json; print(json.dumps('''$GRAPHQL'''))")}"
}

render() {
  python3 -c "
import json, sys
d = json.load(sys.stdin)
post = (d.get('data') or {}).get('post')
if not post:
    print('找不到 post（slug 对错？还没发布？）:', json.dumps(d)[:200]); sys.exit(0)
print(f\"{post['name']} — {post['tagline']}\")
print(f\"票数 {post['votesCount']} · 评论 {post['commentsCount']} · 日排名 {post.get('dailyRank') or '—'} · 评分 {post.get('reviewsRating') or '—'}\")
for c in (post.get('comments') or {}).get('nodes', []):
    body = c['body'][:80].replace(chr(10), ' ')
    print(f\"  · {c['user']['name']}: {body}\")
"
}

TOKEN=$(get_token)
if [ "$WATCH" != "--watch" ]; then
  snapshot | render
  exit 0
fi

last=""
while true; do
  current=$(snapshot)
  summary=$(echo "$current" | python3 -c "
import json, sys
d = json.load(sys.stdin)
p = (d.get('data') or {}).get('post') or {}
print(f\"{p.get('votesCount')},{p.get('commentsCount')},{p.get('dailyRank')}\")
")
  if [ "$summary" != "$last" ]; then
    echo "── $(date '+%H:%M:%S') ──"
    echo "$current" | render
    last="$summary"
  fi
  sleep 120
done
