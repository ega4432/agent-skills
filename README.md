# agent-skills

[`gh skill`](https://cli.github.com/) で配布する agent 用スキル集。

## 収録スキル

| スキル | 説明 |
|---|---|
| [`macos-calendar`](./skills/macos-calendar/) | macOS 純正 Calendar.app から指定日（today / yesterday / YYYY-MM-DD 等）の予定を取得する。osascript + node を使うため Chrome や Web ログイン不要。初回実行時に Calendar.app 制御の TCC 許可が必要。 |

## インストール

```bash
# スキルを検索
gh skill search macos-calendar

# 導入前にプレビュー
gh skill preview ega4432/agent-skills macos-calendar

# インストール
gh skill install ega4432/agent-skills macos-calendar

# 導入済みスキル一覧
gh skill list
```

## License

[MIT](./LICENSE)
