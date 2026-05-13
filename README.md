# ghbar

GitHub でレビュー依頼されている Open PR の件数と一覧を macOS メニューバーに常時表示する [SwiftBar](https://github.com/swiftbar/SwiftBar) プラグインです。

![menubar example](https://img.shields.io/badge/menubar-PR%3A3-orange)

## 機能

- メニューバーに件数を表示（例: `PR:3`）
  - 0件: グレー / 1〜4件: オレンジ / 5件以上: 赤
- ドロップダウンに各 PR を表示（クリックでブラウザを開く）
- `owner/repo • author` をサブ行に表示
- 「GitHub で全部見る」リンクと Refresh ボタン
- 2 分ごとに自動更新

## 必要なもの

- macOS
- [SwiftBar](https://github.com/swiftbar/SwiftBar) — `brew install --cask swiftbar`
- [gh CLI](https://cli.github.com/) — `brew install gh` & `gh auth login`
- [jq](https://stedolan.github.io/jq/) — `brew install jq`

## インストール

```sh
git clone https://github.com/<your-account>/ghbar.git ~/repos/ghbar
mkdir -p ~/.config/swiftbar/plugins
ln -s ~/repos/ghbar/github-review-requests.2m.sh \
      ~/.config/swiftbar/plugins/github-review-requests.2m.sh
```

SwiftBar の Plugin Folder には `~/.config/swiftbar/plugins` を指定してください。

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
