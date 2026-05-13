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

# 件数に応じて色を変える
if [ "$COUNT" -eq 0 ]; then
  COLOR="gray"
elif [ "$COUNT" -ge 5 ]; then
  COLOR="red"
else
  COLOR="orange"
fi

# メニューバー表示
echo "PR:${COUNT} | color=${COLOR}"
echo "---"

# 全部見るリンク
echo "GitHub で全部見る | href=${SEARCH_URL}"
echo "---"

# 各 PR を 2 行ずつ出力
if [ "$COUNT" -gt 0 ]; then
  echo "$JSON" | jq -r '.[] | [.title, .url, .repository.nameWithOwner, .author.login] | @tsv' \
    | while IFS=$'\t' read -r TITLE URL REPO AUTHOR; do
        # 1行目: タイトル（クリックでブラウザを開く）
        echo "${TITLE} | href=${URL}"
        # 2行目: リポジトリ • 著者（小さくグレー）
        echo "${REPO} • ${AUTHOR} | size=11 color=gray href=${URL}"
      done
else
  echo "レビュー依頼中の PR はありません | color=gray"
fi

echo "---"
echo "Refresh | refresh=true"
