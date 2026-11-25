#!/usr/bin/env bash
# <bitbar.title>GitHub Review Requests</bitbar.title>
# <bitbar.version>v1.0</bitbar.version>
# <bitbar.author>kazuyuki</bitbar.author>
# <bitbar.desc>レビュー依頼と、自分の Open PR に届いた要対応のレビュー指摘を表示</bitbar.desc>
# <bitbar.dependencies>gh, jq</bitbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>

# SwiftBar から起動されると PATH が最小限なので Homebrew のパスを通す
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

SEARCH_URL="https://github.com/search?q=review-requested%3A%40me+is%3Apr+is%3Aopen&type=pullrequests"

# 各クエリは parent.items に対象の connection を返す。
graphql_nodes() {
  local query=$1 id=${2:-} cursor=${3:-} page
  local -a args
  while :; do
    args=(-f "query=$query")
    if [ -n "$id" ]; then args+=(-f "id=$id"); fi
    if [ -n "$cursor" ]; then args+=(-f "after=$cursor"); fi
    page=$(gh api graphql "${args[@]}") || return 1
    jq -c '.data.parent.items.nodes[]' <<< "$page" || return 1
    cursor=$(jq -er '.data.parent.items.pageInfo |
      if .hasNextPage then .endCursor else "" end' <<< "$page") || return 1
    [ -n "$cursor" ] || break
  done
}

authored_prs_with_reviews() {
  local review_fields='id state submittedAt viewerDidAuthor author { __typename login }
    bodyText url comments(last: 1) { nodes { url } }'
  local event_fields='__typename
    ... on ReviewRequestedEvent { createdAt actor { login } requestedReviewer { ... on User { login } } }
    ... on ReviewDismissedEvent { previousReviewState review { id } }'
  local event_types='[REVIEW_REQUESTED_EVENT, REVIEW_DISMISSED_EVENT]'
  local page_info='pageInfo { hasNextPage endCursor }'
  local reviews="reviews(first: 50) { $page_info nodes { $review_fields } }"
  local events="timelineItems(first: 50, itemTypes: $event_types) { $page_info nodes { $event_fields } }"
  local pr_query="query(\$after: String) {
    parent: viewer { items: pullRequests(first: 20, after: \$after, states: OPEN) {
      $page_info nodes { id title url author { login } $reviews events: $events }
    } }
  }"

  # 通常は PR の一覧と履歴を一括取得する。長い履歴だけ同じ PR の続きを取得する。
  local pr id kind cursor connection query extra
  graphql_nodes "$pr_query" | while IFS= read -r pr; do
    id=$(jq -er .id <<< "$pr") || return 1
    for kind in reviews events; do
      cursor=$(jq -r --arg kind "$kind" '.[$kind].pageInfo | select(.hasNextPage) | .endCursor' <<< "$pr")
      [ -n "$cursor" ] || continue
      if [ "$kind" = reviews ]; then
        connection="reviews(first: 100, after: \$after) { $page_info nodes { $review_fields } }"
      else
        connection="timelineItems(first: 100, after: \$after, itemTypes: $event_types) { $page_info nodes { $event_fields } }"
      fi
      query="query(\$id: ID!, \$after: String) {
        parent: node(id: \$id) { ... on PullRequest { items: $connection } }
      }"
      extra=$(graphql_nodes "$query" "$id" "$cursor") || return 1
      pr=$(printf '%s\n' "$pr" "$extra" | jq -cs --arg kind "$kind" '.[1:] as $more | .[0] | .[$kind].nodes += $more') || return 1
    done
    printf '%s\n' "$pr"
  done
}

fetch_feedback() (
  set -o pipefail
  # FIX の判定には提出時の状態を使う。指摘にはリンクがあり、承認・再依頼にはない。
  # 同じ秒に指摘と解消が記録された場合は解消を優先する。
  authored_prs_with_reviews | jq -sc '
    def outstanding:
      .author.login as $me |
      .events.nodes as $events |
      (INDEX($events[] | select(.review != null); .review.id)) as $dismissals |
      [
        ($events[] | select(.__typename == "ReviewRequestedEvent" and .actor.login == $me)
          | select(.requestedReviewer.login != null)
          | {login: .requestedReviewer.login, at: .createdAt}),
        (.reviews.nodes[] | select(.author.__typename == "User" and (.viewerDidAuthor | not) and .submittedAt)
          | ($dismissals[.id].previousReviewState // .state) as $state
          | .comments.nodes[0].url as $comment
          | {login: .author.login, at: .submittedAt} +
            (if $state == "APPROVED" then {}
             elif $state == "CHANGES_REQUESTED" or
               ($state == "COMMENTED" and ($comment != null or (.bodyText | test("\\S"))))
             then {url: ($comment // .url)}
             else empty end))
      ]
      | group_by(.login)
      | map(max_by([.at, (.url == null)]) | select(.url != null));
    map({title, url, reviewers: outstanding} | select(.reviewers | length > 0))'
)

# gh でレビュー依頼中の Open PR を取得（JSON）
JSON=$(gh search prs --review-requested=@me --state=open \
  --json title,url,repository,author,isDraft \
  --limit 50 2>/dev/null)
GH_EXIT=$?

# エラー時のフォールバック
if [ $GH_EXIT -ne 0 ] || [ -z "$JSON" ]; then
  COUNT="?"
  ALL_COUNT="?"
else
  ALL_COUNT=$(echo "$JSON" | jq 'length')
  COUNT=$(echo "$JSON" | jq '[.[] | select(.isDraft == false)] | length')
fi

# 自分がレビュー提出済みだが最新レビューが COMMENTED の PR（approve/request_changes 未実施）を取得
ME=$(gh api user --jq .login 2>/dev/null)
PENDING_JSON="[]"
if [ "$COUNT" != "?" ] && [ -n "$ME" ]; then
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

if FIX_JSON=$(fetch_feedback 2>/dev/null); then
  FIX_COUNT=$(jq 'length' <<< "$FIX_JSON")
else
  FIX_COUNT="?"
fi

# 前回件数を読み込んで、増えていれば音 + 通知センターで知らせる
STATE_DIR="${HOME}/.cache/ghbar"
STATE_FILE="${STATE_DIR}/last_count"
mkdir -p "$STATE_DIR"
PREV_COUNT=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
# 数値でなければ 0 にフォールバック
[[ "$PREV_COUNT" =~ ^[0-9]+$ ]] || PREV_COUNT=0

if [ "$COUNT" != "?" ] && [ "$COUNT" -gt "$PREV_COUNT" ]; then
  DIFF=$((COUNT - PREV_COUNT))
  # システム音 (Glass) を鳴らす
  afplay /System/Library/Sounds/Glass.aiff >/dev/null 2>&1 &
  # 通知センターに表示
  osascript -e "display notification \"レビュー依頼が ${DIFF} 件増えました (合計 ${COUNT} 件)\" with title \"GitHub Review Requests\" sound name \"Glass\"" >/dev/null 2>&1 &
fi

if [ "$COUNT" != "?" ]; then echo "$COUNT" > "$STATE_FILE"; fi

# 件数に応じて色を変える
if [ "$COUNT" != "?" ] && [ "$COUNT" -ge 5 ]; then
  COLOR="red"
elif [[ "$COUNT" =~ ^[1-9] || "$PENDING_COUNT" != 0 || "$FIX_COUNT" =~ ^[1-9] ]]; then
  COLOR="orange"
else
  COLOR="gray"
fi

# メニューバー表示（保留分が 0 のときは +N を省く）
BADGE="REV:${COUNT}"
if [ "$PENDING_COUNT" -gt 0 ]; then BADGE+="+${PENDING_COUNT}"; fi
if [ "$FIX_COUNT" != 0 ]; then BADGE+=" FIX:${FIX_COUNT}"; fi
echo "${BADGE} | color=${COLOR}"
echo "---"

# 全部見るリンク
echo "GitHub で全部見る | href=${SEARCH_URL}"
echo "---"

# レビュー依頼セクション
echo "レビュー依頼 (${ALL_COUNT}) | size=11 color=gray"
if [ "$COUNT" = "?" ]; then
  echo "gh コマンドでエラー | color=red"
  echo "gh auth status を確認してください | href=https://cli.github.com/"
elif [ "$ALL_COUNT" -gt 0 ]; then
  echo "$JSON" | jq -r '.[] | [.title, .url, .repository.nameWithOwner, .author.login, (.isDraft|tostring)] | @tsv' \
    | while IFS=$'\t' read -r TITLE URL REPO AUTHOR ISDRAFT; do
        if [ "$ISDRAFT" = "true" ]; then
          echo "${TITLE} [Draft] | href=${URL} color=gray"
        else
          echo "${TITLE} | href=${URL}"
        fi
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

if [ "$FIX_COUNT" != 0 ]; then
  echo "---"
  echo "自分の PR に届いた指摘 (${FIX_COUNT}) | size=11 color=gray"
  if [ "$FIX_COUNT" = "?" ]; then
    echo "レビュー履歴の取得に失敗しました | color=red"
  else
    jq -r '.[] |
      ((.title | gsub("[\\r\\n]"; " ") | gsub("[|]"; "｜")) + " | href=" + .url),
      (.reviewers[] | "@" + .login + " | size=11 color=gray href=" + .url)' <<< "$FIX_JSON"
  fi
fi

echo "---"
echo "Refresh | refresh=true"
