#!/usr/bin/env bash
#
# calendar-events.sh — macOS 純正 Calendar.app から指定日の予定を取得する
#
# 使い方:
#   ./calendar-events.sh [DATE] [options]
#     DATE                  today(既定) | yesterday | YYYY-MM-DD
#   options:
#     --calendar <名前>     対象カレンダー名 (既定: 予定表)
#     --exclude-declined    辞退/欠席の予定を除外 (件名の 辞退:/Declined: 接頭辞、
#                           または --me で指定した本人の status=declined)
#     --me <email>          本人メール。--exclude-declined と併用して自分の辞退を判定
#     --out-dir <dir>       JSON の出力先ディレクトリ
#                           (既定: ${XDG_CACHE_HOME:-$HOME/.cache}/macos-calendar-cli)
#     --json-only           人間向けの表を出さず、JSON パスのみ表示
#
# 出力:
#   - 出力先ディレクトリに calendar-events-<YYYY-MM-DD>.json (イベント配列)
#   - 標準出力に Markdown 表 + Data: <path>
#
# 前提: node が PATH にあること。初回実行時に Calendar.app 制御の許可(TCC)が要る。

set -euo pipefail

# ---- 引数パース ----------------------------------------------------------
DATE_ARG="today"
CAL="予定表"
EXCLUDE_DECLINED=0
ME=""
JSON_ONLY=0
OUT_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/macos-calendar-cli"

while [ $# -gt 0 ]; do
  case "$1" in
    --calendar)         CAL="${2:-}"; shift 2 ;;
    --exclude-declined) EXCLUDE_DECLINED=1; shift ;;
    --me)               ME="${2:-}"; shift 2 ;;
    --out-dir)          OUT_DIR="${2:-}"; shift 2 ;;
    --json-only)        JSON_ONLY=1; shift ;;
    -h|--help)
      sed -n '2,21p' "$0"; exit 0 ;;
    -*)
      echo "unknown option: $1" >&2; exit 2 ;;
    *)
      DATE_ARG="$1"; shift ;;
  esac
done

# ---- 日付解決 (Asia/Tokyo 前提はローカルタイム基準) -----------------------
case "$DATE_ARG" in
  today)     TARGET="$(date +%Y-%m-%d)" ;;
  yesterday) TARGET="$(date -v-1d +%Y-%m-%d)" ;;
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) TARGET="$DATE_ARG" ;;
  *)
    echo "日付は today / yesterday / YYYY-MM-DD で指定してください: $DATE_ARG" >&2
    exit 2 ;;
esac

Y="${TARGET%%-*}"
M="${TARGET:5:2}"
D="${TARGET:8:2}"

# ---- 対象カレンダーの存在確認 --------------------------------------------
# 見つからなければ利用可能な一覧を出して終了（環境ごとに名前が異なるため）。
AVAIL="$(osascript -e 'tell application "Calendar" to get name of every calendar' 2>/dev/null || true)"
if ! printf '%s' "$AVAIL" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -qxF "$CAL"; then
  {
    echo "カレンダー '$CAL' が見つかりません。--calendar で指定してください。"
    echo "利用可能なカレンダー:"
    printf '%s\n' "$AVAIL" | tr ',' '\n' | sed 's/^ *//;s/ *$//;s/^/  - /'
  } >&2
  exit 3
fi

# ---- AppleScript でイベント抽出 ------------------------------------------
# US(\x1f)=フィールド区切り, RS(\x1e)=レコード区切り。
# フィールド順: uid, summary, startISO, endISO, allday, location, notes, attendees
# attendees は "name<email>[status]" を ";;" で連結。
RAW="$(osascript - "$CAL" "$Y" "$M" "$D" <<'APPLE'
on run argv
	set calName to item 1 of argv
	set Y to (item 2 of argv) as integer
	set M to (item 3 of argv) as integer
	set D to (item 4 of argv) as integer

	set d0 to (current date)
	set day of d0 to 1
	set year of d0 to Y
	set month of d0 to M
	set day of d0 to D
	set time of d0 to 0
	set d1 to d0 + (1 * days)

	set FS to (character id 31)
	set RS to (character id 30)
	set out to ""

	tell application "Calendar"
		tell calendar calName
			set evs to (every event whose start date ≥ d0 and start date < d1)
			repeat with e in evs
				set uidv to my safe(uid of e)
				set summ to my safe(summary of e)
				set sISO to my iso(start date of e)
				set eISO to my iso(end date of e)
				set adv to (allday event of e) as string
				set locv to my safe(location of e)
				set ntv to my safe(description of e)

				set att to ""
				repeat with a in (attendees of e)
					set pr to (properties of a)
					set an to my safe(display name of pr)
					set ae to my safe(email of pr)
					set asx to ""
					try
						set asx to (participation status of pr) as string
					end try
					if att is not "" then set att to att & ";;"
					set att to att & an & "<" & ae & ">[" & asx & "]"
				end repeat

				set rec to uidv & FS & summ & FS & sISO & FS & eISO & FS & adv & FS & locv & FS & ntv & FS & att
				if out is not "" then set out to out & RS
				set out to out & rec
			end repeat
		end tell
	end tell
	return out
end run

on safe(v)
	if v is missing value then return ""
	return v as string
end safe

on iso(d)
	return (my pad(year of d, 4)) & "-" & (my pad((month of d) as integer, 2)) & "-" & (my pad(day of d, 2)) & "T" & (my pad(hours of d, 2)) & ":" & (my pad(minutes of d, 2)) & ":" & (my pad(seconds of d, 2))
end iso

on pad(n, w)
	set s to (n as integer) as string
	repeat while (length of s) < w
		set s to "0" & s
	end repeat
	return s
end pad
APPLE
)"

# ---- Node で整形 (重複排除 / ソート / URL抽出 / JSON生成) -----------------
mkdir -p "$OUT_DIR"
OUT_JSON="$OUT_DIR/calendar-events-${TARGET}.json"

TARGET="$TARGET" OUT_JSON="$OUT_JSON" EXCLUDE_DECLINED="$EXCLUDE_DECLINED" \
ME="$ME" JSON_ONLY="$JSON_ONLY" RAW="$RAW" node <<'NODE'
const fs = require("fs");
const FS = "\x1f", RS = "\x1e";
const {
  TARGET, OUT_JSON, ME,
} = process.env;
const EXCLUDE_DECLINED = process.env.EXCLUDE_DECLINED === "1";
const JSON_ONLY = process.env.JSON_ONLY === "1";
const raw = process.env.RAW || "";

function stripHtml(s) {
  if (!s) return "";
  return s
    .replace(/\r\n?/g, "\n")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|li|tr)>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n))
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/[ \t]*\n[ \t]*/g, "\n")
    .trim();
}

function extractUrl(notes) {
  if (!notes) return "";
  const urls = notes.match(/https?:\/\/[^\s"'<>）】\]]+/g) || [];
  if (!urls.length) return "";
  const teams = urls.find((u) => /teams\.microsoft\.com/i.test(u));
  return teams || urls[0];
}

function parseAttendees(s) {
  if (!s) return [];
  return s.split(";;").map((tok) => {
    const m = tok.match(/^(.*)<([^>]*)>\[([^\]]*)\]$/);
    if (!m) return { name: tok, email: "", status: "" };
    return { name: m[1].trim(), email: m[2].trim(), status: m[3].trim() };
  });
}

const declinedPrefix = /^\s*(辞退|欠席|Declined)\s*[:：]/;

let events = raw
  .split(RS)
  .map((r) => r.replace(/\n+$/, ""))
  .filter((r) => r.trim() !== "")
  .map((rec) => {
    const f = rec.split(FS);
    const notesRaw = f[6] || "";
    const attendees = parseAttendees(f[7] || "");
    return {
      uid: f[0] || "",
      summary: f[1] || "",
      start: f[2] || "",
      end: f[3] || "",
      allDay: (f[4] || "") === "true",
      location: f[5] || "",
      meetingUrl: extractUrl(notesRaw),
      attendees,
      notes: notesRaw,
      notesText: stripHtml(notesRaw),
    };
  });

// uid で重複排除 (uid が空なら summary+start で代替キー)
const seen = new Map();
for (const ev of events) {
  const key = ev.uid || `${ev.summary}@${ev.start}`;
  if (!seen.has(key)) seen.set(key, ev);
}
events = [...seen.values()];

// 辞退の除外
if (EXCLUDE_DECLINED) {
  events = events.filter((ev) => {
    if (declinedPrefix.test(ev.summary)) return false;
    if (ME) {
      const me = ev.attendees.find(
        (a) => a.email.toLowerCase() === ME.toLowerCase()
      );
      if (me && /declined/i.test(me.status)) return false;
    }
    return true;
  });
}

// 開始時刻でソート
events.sort((a, b) => (a.start < b.start ? -1 : a.start > b.start ? 1 : 0));

fs.writeFileSync(OUT_JSON, JSON.stringify(events, null, 2) + "\n");

// ---- 人間向け出力 --------------------------------------------------------
function hhmm(iso) {
  return (iso || "").slice(11, 16);
}
function timeCol(ev) {
  if (ev.allDay) return "終日";
  const s = hhmm(ev.start);
  const e = hhmm(ev.end);
  return e ? `${s}–${e}` : s;
}
function cell(s) {
  return (s || "").replace(/\|/g, "\\|").replace(/\n/g, " ").trim();
}

if (events.length === 0) {
  console.log(`対象日 (${TARGET}) に予定はありません。`);
} else if (!JSON_ONLY) {
  console.log("| 時刻 | 件名 | 場所 |");
  console.log("|---|---|---|");
  for (const ev of events) {
    console.log(`| ${timeCol(ev)} | ${cell(ev.summary)} | ${cell(ev.location)} |`);
  }
  console.log("");
}
console.log(`Data: ${OUT_JSON}`);
NODE
