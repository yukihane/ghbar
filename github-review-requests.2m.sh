#!/usr/bin/env bash
# <bitbar.title>GitHub Review Requests</bitbar.title>
# <bitbar.version>v1.0</bitbar.version>
# <bitbar.author>kazuyuki</bitbar.author>
# <bitbar.desc>自分にレビュー依頼されている Open PR の一覧を表示</bitbar.desc>
# <bitbar.dependencies>gh, jq</bitbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>

# SwiftBar から起動されると PATH が最小限なので Homebrew のパスを通す
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

SEARCH_URL="https://github.com/search?q=review-requested%3A%40me+is%3Apr+is%3Aopen&type=pullrequests"

# gh でレビュー依頼中の Open PR を取得（JSON）
JSON=$(gh search prs --review-requested=@me --state=open \
  --json title,url,repository,author \
  --limit 50 2>/dev/null)
GH_EXIT=$?

# エラー時のフォールバック
if [ $GH_EXIT -ne 0 ] || [ -z "$JSON" ]; then
  echo "PR:? | color=gray"
  echo "---"
  echo "gh コマンドでエラー | color=red"
  echo "gh auth status を確認してください | href=https://cli.github.com/"
  echo "---"
  echo "Refresh | refresh=true"
  exit 0
fi

COUNT=$(echo "$JSON" | jq 'length')

# 自分がレビュー提出済みだが最新レビューが COMMENTED の PR（approve/request_changes 未実施）を取得
ME=$(gh api user --jq .login 2>/dev/null)
PENDING_JSON="[]"
if [ -n "$ME" ]; then
  REVIEWED_JSON=$(gh search prs --reviewed-by=@me --state=open \
    --json title,url,repository,author,number \
    --limit 50 2>/dev/null)
  if [ -n "$REVIEWED_JSON" ]; then
    # review-requested に含まれる URL は除外（再依頼ケース）
    REQUESTED_URLS=$(echo "$JSON" | jq -r '.[].url')
    PENDING_JSON=$(echo "$REVIEWED_JSON" | jq -c --arg me "$ME" '.[] | select(.author.login != $me)' | while read -r row; do
      URL=$(echo "$row" | jq -r .url)
      if echo "$REQUESTED_URLS" | grep -qx "$URL"; then
        continue
      fi
      REPO=$(echo "$row" | jq -r .repository.nameWithOwner)
      NUM=$(echo "$row" | jq -r .number)
      LAST_STATE=$(gh api "repos/${REPO}/pulls/${NUM}/reviews" \
        --jq "[.[] | select(.user.login==\"${ME}\")] | last | .state" 2>/dev/null)
      if [ "$LAST_STATE" = "COMMENTED" ]; then
        echo "$row"
      fi
    done | jq -s '.')
    [ -z "$PENDING_JSON" ] && PENDING_JSON="[]"
  fi
fi
PENDING_COUNT=$(echo "$PENDING_JSON" | jq 'length')

# 前回件数を読み込んで、増えていれば音 + 通知センターで知らせる
STATE_DIR="${HOME}/.cache/ghbar"
STATE_FILE="${STATE_DIR}/last_count"
mkdir -p "$STATE_DIR"
PREV_COUNT=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
# 数値でなければ 0 にフォールバック
[[ "$PREV_COUNT" =~ ^[0-9]+$ ]] || PREV_COUNT=0

if [ "$COUNT" -gt "$PREV_COUNT" ]; then
  DIFF=$((COUNT - PREV_COUNT))
  # システム音 (Glass) を鳴らす
  afplay /System/Library/Sounds/Glass.aiff >/dev/null 2>&1 &
  # 通知センターに表示
  osascript -e "display notification \"レビュー依頼が ${DIFF} 件増えました (合計 ${COUNT} 件)\" with title \"GitHub Review Requests\" sound name \"Glass\"" >/dev/null 2>&1 &
fi

echo "$COUNT" > "$STATE_FILE"

# 件数に応じて色を変える
if [ "$COUNT" -eq 0 ] && [ "$PENDING_COUNT" -eq 0 ]; then
  COLOR="gray"
elif [ "$COUNT" -ge 5 ]; then
  COLOR="red"
else
  COLOR="orange"
fi

# メニューバー表示（保留分が 0 のときは +N を省く）
if [ "$PENDING_COUNT" -gt 0 ]; then
  BADGE="PR:${COUNT}+${PENDING_COUNT}"
else
  BADGE="PR:${COUNT}"
fi
echo "${BADGE} | color=${COLOR}"
echo "---"

# 全部見るリンク
echo "GitHub で全部見る | href=${SEARCH_URL}"
echo "---"

# レビュー依頼セクション
echo "レビュー依頼 (${COUNT}) | size=11 color=gray"
if [ "$COUNT" -gt 0 ]; then
  echo "$JSON" | jq -r '.[] | [.title, .url, .repository.nameWithOwner, .author.login] | @tsv' \
    | while IFS=$'\t' read -r TITLE URL REPO AUTHOR; do
        echo "${TITLE} | href=${URL}"
        echo "${REPO} • ${AUTHOR} | size=11 color=gray href=${URL}"
      done
else
  echo "なし | color=gray"
fi

# コメント保留セクション（approve/request_changes 未実施）
if [ "$PENDING_COUNT" -gt 0 ]; then
  echo "---"
  echo "コメント保留 (${PENDING_COUNT}) | size=11 color=gray"
  echo "$PENDING_JSON" | jq -r '.[] | [.title, .url, .repository.nameWithOwner, .author.login] | @tsv' \
    | while IFS=$'\t' read -r TITLE URL REPO AUTHOR; do
        echo "${TITLE} | href=${URL}"
        echo "${REPO} • ${AUTHOR} | size=11 color=gray href=${URL}"
      done
fi

echo "---"
echo "Refresh | refresh=true"
