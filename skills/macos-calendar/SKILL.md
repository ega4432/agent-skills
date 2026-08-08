---
name: macos-calendar
description: >
  macOS 純正 Calendar.app から指定日（today / yesterday / 先週の金曜日 / YYYY-MM-DD 等）の
  予定を取得する。「今日の予定を教えて」「昨日のカレンダー見せて」「Mac の予定表を確認して」の
  ような依頼で使う。osascript + node を使うため Chrome や Web ログインは不要。初回実行時に
  Calendar.app 制御の TCC 許可が必要。
license: MIT
compatibility: macOS 専用。node と osascript（標準搭載）が必要。初回に Calendar.app 制御の TCC 許可が要る。
---

# macOS Calendar

macOS 純正 **Calendar.app** から指定日の予定を取得し、Markdown 表 + JSON アーティファクトで返す。
Exchange 等の業務予定も Calendar.app に同期されていればネイティブに取得できる。

実行スクリプトは**このスキル内の `scripts/calendar-events.sh`**（SKILL.md からの相対パス）に
同梱されている。まずスキル自身のディレクトリの絶対パスが分かるなら、その
`scripts/calendar-events.sh` をそのまま使う（`$CLAUDE_PLUGIN_ROOT` 等ホストが与える値があれば
それも使ってよい）。

分からない場合は、**ホスト／スコープ非依存**の次のスニペットで解決する。`gh skill install` は
Claude Code 以外（Cursor / Codex / Copilot / Gemini CLI など）にも入り、配置先は
`.claude/skills/`・`.agents/skills/`・`~/.<host>/skills/` などホストごとに異なるため、複数候補を
探索してから最後に `find` でフォールバックする:

```bash
SKILL_NAME="macos-calendar"; REL="scripts/calendar-events.sh"; SCRIPT=""
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
shopt -s nullglob 2>/dev/null || true

# 1) 既知のスキルルートを優先探索（project: .claude/.agents 等、user: ~/.<host>/skills）
for cand in \
  ${CLAUDE_PLUGIN_ROOT:+"$CLAUDE_PLUGIN_ROOT/$REL"} \
  ${GIT_ROOT:+"$GIT_ROOT/.claude/skills/$SKILL_NAME/$REL"} \
  ${GIT_ROOT:+"$GIT_ROOT/.agents/skills/$SKILL_NAME/$REL"} \
  "$PWD/.claude/skills/$SKILL_NAME/$REL" \
  "$PWD/.agents/skills/$SKILL_NAME/$REL" \
  "$HOME"/.*/skills/"$SKILL_NAME/$REL" \
  "$HOME"/.config/*/skills/"$SKILL_NAME/$REL"; do
  [ -f "$cand" ] && { SCRIPT="$cand"; break; }
done

# 2) 最終フォールバック: プロジェクト配下を bounded find
if [ -z "$SCRIPT" ]; then
  SCRIPT="$(find "${GIT_ROOT:-$PWD}" -maxdepth 7 -type f -name "calendar-events.sh" -path "*/$SKILL_NAME/scripts/*" 2>/dev/null | head -n1)"
fi

[ -n "$SCRIPT" ] || { echo "$SKILL_NAME スクリプト未検出。gh skill install で導入を促す。" >&2; exit 1; }
```

以降このパスを `"$SCRIPT"` として使う。

## Prerequisites

- `node` と `osascript`（標準搭載）が `PATH` にあること。
- 対象の予定が Calendar.app に同期されていること。
- **初回実行時**、「ターミナル（または Claude）が Calendar.app を制御することを許可しますか？」という
  TCC プロンプトが出る。許可が必要（システム設定 > プライバシーとセキュリティ > オートメーション）。
  **Claude 自身はこの許可を付与できない** — ユーザーに手動で許可してもらう。
- 上記の解決で `$SCRIPT` が得られること。見つからなければ `gh skill install` での導入を促して停止する。

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
# $SCRIPT は冒頭で解決したパス
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
| `$SCRIPT` 未検出 | user/project どちらにも配置が無い。`gh skill install ega4432/agent-skills macos-calendar` を案内して停止。 |

## Non-goals

- 予定の作成・変更・削除はしない（読み取り専用）。
- 1 回の実行で複数日は扱わない（1 日ずつ）。
- TCC 許可の自動付与はしない（ユーザーが手動で許可する）。
- 生成した JSON をコミット・外部送信しない。
