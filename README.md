# ghbar

GitHub でレビュー依頼されている Open PR の件数と一覧を macOS メニューバーに常時表示する [SwiftBar](https://github.com/swiftbar/SwiftBar) プラグインです。

## 機能

- メニューバーに件数を表示（例: `PR:3`、コメント保留があるときは `PR:3+1`）
  - 0件: グレー / 1〜4件: オレンジ / 5件以上: 赤
  - Draft 状態の PR は件数（色判定含む）には含めない。ドロップダウンの「レビュー依頼」一覧には `[Draft]` 付きで表示され続ける
  - `+N` は「自分がレビュアーに指定されていたが、コメントのみで提出した（approve / request changes 未実施）」PR の件数。`review-requested:@me` からは外れるが対応が残っているものを可視化する。自分が author の PR は除外。
- ドロップダウンに各 PR を「レビュー依頼」「コメント保留」の2セクションで表示（クリックでブラウザを開く）
- `owner/repo • author` をサブ行に表示
- 「GitHub で全部見る」リンクと Refresh ボタン
- 2 分ごとに自動更新
- **レビュー依頼の件数（Draft除く）が増えたときに音 (Glass) + 通知センターで知らせる**（前回件数は `~/.cache/ghbar/last_count` に保存）。Draft PR がレビュー可能になった場合もこの件数増加として検知され、同様に通知される

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
