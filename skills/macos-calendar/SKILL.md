---
name: macos-calendar
description: >
  macOS 純正 Calendar.app から指定日（today / yesterday / 先週の金曜日 / YYYY-MM-DD 等）の
  予定を取得する。「今日の予定を教えて」「昨日のカレンダー見せて」「Mac の予定表を確認して」の
  ような依頼で使う。osascript + node を使うため Chrome や Web ログインは不要。初回実行時に
  Calendar.app 制御の TCC 許可が必要。
---

# macOS Calendar

macOS 純正 **Calendar.app** から指定日の予定を取得し、Markdown 表 + JSON アーティファクトで返す。
Exchange 等の業務予定も Calendar.app に同期されていればネイティブに取得できる。

同梱スクリプトを絶対パスで実行する:

```
SCRIPT="$HOME/.claude/skills/macos-calendar/calendar-events.sh"
```

## Prerequisites

- `node` と `osascript`（標準搭載）が `PATH` にあること。
- 対象の予定が Calendar.app に同期されていること。
- **初回実行時**、「ターミナル（または Claude）が Calendar.app を制御することを許可しますか？」という
  TCC プロンプトが出る。許可が必要（システム設定 > プライバシーとセキュリティ > オートメーション）。
  **Claude 自身はこの許可を付与できない** — ユーザーに手動で許可してもらう。
- `$SCRIPT` が存在すること。無ければユーザーに導入（リポジトリからの配置）を促して停止する。

## Steps

### 1. 対象日を解決する

ユーザーの言い回しを `currentDate`（特に指定がなければ `Asia/Tokyo` / `+09:00`）を基準に、
スクリプトが解釈できる形式へ変換する:

- `today` / `yesterday` はそのまま渡せる。
- それ以外（「先週の金曜日」「8月7日」など）は Claude 側で **`YYYY-MM-DD`** に落として渡す。
  スクリプトが直接理解するのは `today` / `yesterday` / `YYYY-MM-DD` の 3 形式のみ。
- 曖昧なとき（例: 「金曜日」で今週/先週が不明）は `AskUserQuestion` で確認する。

### 2. スクリプトを実行する

```bash
SCRIPT="$HOME/.claude/skills/macos-calendar/calendar-events.sh"
"$SCRIPT" <DATE> [--calendar <名前>] [--exclude-declined] [--me <email>] [--out-dir <dir>]
```

- JSON は既定で `${XDG_CACHE_HOME:-$HOME/.cache}/macos-calendar-cli/` に出力される
  （作業ディレクトリ＝ユーザーのプロジェクトは汚さない）。標準出力の `Data: <path>` が実パス。
- 生成 JSON には参加者メール・議事メモ・会議URL 等の**機微情報**が含まれる。
  コミット・外部送信はしない。

### 3. カレンダーが見つからない場合（exit 3）

指定（または既定 `予定表`）のカレンダー名が無いと、スクリプトは**利用可能なカレンダー一覧**を
出して exit 3 で終わる。その一覧をユーザーに提示し、`--calendar "<名前>"` で指定するよう促す。
**勝手に別名で再試行しない。**

### 4. 結果を提示する

スクリプト標準出力の Markdown 表（`時刻 / 件名 / 場所`）と `Data: <path>` をそのまま提示する。
必要に応じて、`Data:` の JSON から `meetingUrl`（会議URL）・`attendees`（参加者）・
`notesText`（整形済みメモ）を読んで補足してよい。予定が無い日はスクリプトが
「対象日 (YYYY-MM-DD) に予定はありません。」と出すので、その旨を伝える。

## Failure modes

| 症状 | 対応 |
|---|---|
| `node` / `osascript` が無い | 導入を案内して停止。 |
| TCC 未許可でイベントが空 | 「システム設定 > プライバシー > オートメーション」で許可するよう案内。**Claude は許可できない**。 |
| カレンダー未検出（exit 3） | 出力された利用可能一覧を提示し、`--calendar` 指定を促す。別名で勝手に再試行しない。 |
| 実行に数十秒かかる | 大人数の会議がある日は参加者取得で時間がかかる。正常挙動として待つ。 |
| `$SCRIPT` が無い | スキルが正しく配置されていない。導入手順を案内して停止。 |

## Non-goals

- 予定の作成・変更・削除はしない（読み取り専用）。
- 1 回の実行で複数日は扱わない（1 日ずつ）。
- TCC 許可の自動付与はしない（ユーザーが手動で許可する）。
- 生成した JSON をコミット・外部送信しない。
