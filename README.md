# ghbar

GitHub で自分に届いたレビュー依頼と、自分の Open PR に届いた要対応のレビュー指摘を macOS メニューバーに表示する [SwiftBar](https://github.com/swiftbar/SwiftBar) プラグインです。

## 機能

メニューバーの表示例は `REV:3+1 FIX:2` です。

- `REV:3` は自分にレビュー依頼が来ている PR の件数です。Draft はドロップダウンに `[Draft]` 付きで表示し、件数からは除外します。
- `+1` は、他の人の PR で自分の最新レビューがコメントのみの保留件数です。再依頼が来た PR は `REV` に数えます。
- `FIX:2` は、自分の Open PR (Draft を含む) のうち、対応が残っている PR の件数です。「自分の PR に届いた指摘」から PR を、指摘者名からその人の最新の指摘を開けます。

`+N` と `FIX:N` はそれぞれ 0 件なら省略します。全件 0 ならグレー、`REV` が 5 件以上なら赤、それ以外で項目があればオレンジです。2 分ごとに更新し、メニューの Refresh でも再取得できます。

### FIX の判定

人が提出した変更要求、本文や行コメント付きのレビュー、レビュースレッドへの返信を対象とします。自分自身・bot の投稿と、Conversation 欄に直接書かれた通常コメントは対象外です。

指摘した人に自分が再レビューを依頼するか、その人が承認すると、その人の分が解消します。承認時に添えられた行コメントは承認に含めます。その後に新しい指摘が届けば再表示します。たとえば A さんと B さんから指摘があり、A さんだけに再依頼すると、一覧には B さんが残り、件数は `FIX:1` です。スレッドの Resolve 状態は判定に使いません。

`FIX` は更新ごとに GitHub の履歴から計算します。取得に失敗したときは `FIX:?` と表示します。音 (Glass) と通知センターで知らせるのは `REV` の件数が増えたときだけです。その判定に使う前回件数は `~/.cache/ghbar/last_count` に保存します。

## 必要なもの

- macOS
- [SwiftBar](https://github.com/swiftbar/SwiftBar) — `brew install --cask swiftbar`
- [gh CLI](https://cli.github.com/) — `brew install gh` & `gh auth login`
- [jq](https://stedolan.github.io/jq/) — `brew install jq`

## インストール

```sh
# ~/repos にcheckoutする場合の例
mkdir -p ~/repos
git clone https://github.com/yukihane/ghbar.git ~/repos/ghbar
mkdir -p ~/.config/swiftbar/plugins
ln -s ~/repos/ghbar/github-review-requests.2m.sh \
      ~/.config/swiftbar/plugins/github-review-requests.2m.sh
```

SwiftBar初回起動時、Plugin Folder を聞かれますが、上記で作成した `~/.config/swiftbar/plugins` を指定してください。

## カスタマイズ

スクリプトはシンプルな bash です。色のしきい値や検索条件はファイル冒頭〜中盤を編集するだけで変えられます。

### 更新間隔の変更

SwiftBar はファイル名に含まれる `.<時間>.` 部分でリフレッシュ間隔を決めます。デフォルトは `github-review-requests.2m.sh` の `2m`（= 2分ごと）です。間隔を変えたい場合はファイル名をリネームしてください（本体と symlink の両方）。

| ファイル名例 | 間隔 |
| --- | --- |
| `github-review-requests.30s.sh` | 30秒 |
| `github-review-requests.1m.sh` | 1分 |
| `github-review-requests.5m.sh` | 5分 |
| `github-review-requests.1h.sh` | 1時間 |

## License

[GPLv3](./LICENSE)
