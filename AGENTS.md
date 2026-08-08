# AGENTS.md

このファイルは、このリポジトリで作業するエージェントへのガイダンスを提供します。

## このリポジトリについて

`gh skill`（preview）で agent skill を配布するためのモノレポ。各スキルは [Agent Skills 仕様](https://agentskills.io/specification) に沿って `skills/<name>/` に置く。
ビルドやテストは無く、成果物は「検証を通したスキルディレクトリ + GitHub Release タグ」。

## コマンド

```bash
# 全スキルを仕様に照らして検証（非破壊）。編集後は必ず実行する
gh skill publish --dry-run

# 機械的な問題を自動修正（install メタデータ除去など）→ 差分確認してコミット
gh skill publish --fix

# 公開: リポジトリに `agent-skills` トピックを付け、Release を作成する
gh skill publish --tag v0.1.0

# 利用者のインストール方法（既定は project スコープ）
gh skill install ega4432/agent-skills macos-calendar               # project (<repo>/.claude/skills 等)
gh skill install ega4432/agent-skills macos-calendar --scope user  # user (~/.claude/skills)
```

公開（Release 作成）は慎重に行う操作。ユーザーの明示的な指示が無い限り、`--dry-run` 以外の
`gh skill publish` は実行しない。
