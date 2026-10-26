#!/usr/bin/env bash
# Installs statusline.sh into a Claude Code config folder and points settings.json "statusLine" at it.
# Only the "statusLine" key is changed; the old settings.json is kept as settings.json.bak-statusline-<time>.
#   curl -fsSL https://raw.githubusercontent.com/Raidcompany/claude-statusline/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/Raidcompany/claude-statusline/main/install.sh | bash -s -- ~/other/.claude-config
# Works in Git Bash (Windows), macOS bash 3.2 and Linux.
set -u
SRC_URL=${CLAUDE_STATUSLINE_URL:-https://raw.githubusercontent.com/Raidcompany/claude-statusline/main/statusline.sh}
STAMP=$(date +%Y%m%d-%H%M%S)
OS=$(uname -s 2>/dev/null)

say() { printf '%s\n' "$*"; }
fail() { printf '실패: %s\n' "$*" >&2; exit 1; }

# 1) get statusline.sh once (local copy next to this file if there is one, else download)
TMP_SL="${TMPDIR:-${TEMP:-/tmp}}/claude-statusline-$$.sh"
here=""
case ${BASH_SOURCE[0]:-} in */*) here=${BASH_SOURCE[0]%/*};; ?*) here=.;; esac
if [ -n "$here" ] && [ -f "$here/statusline.sh" ]; then
  cp "$here/statusline.sh" "$TMP_SL" || fail "statusline.sh 복사 실패"
else
  command -v curl >/dev/null 2>&1 || fail "curl 이 없습니다"
  curl -fsSL "$SRC_URL" -o "$TMP_SL" || fail "statusline.sh 내려받기 실패: $SRC_URL"
fi
grep -q 'printf .%s. "\$out"' "$TMP_SL" || { rm -f "$TMP_SL"; fail "받은 statusline.sh 가 이상합니다"; }
trap 'rm -f "$TMP_SL"' EXIT

# 2) pick a JSON tool that is already on this computer (nothing is installed)
json_tool=${CLAUDE_STATUSLINE_JSON_TOOL:-}
if [ -n "$json_tool" ]; then :
elif command -v jq >/dev/null 2>&1; then json_tool=jq
elif command -v node >/dev/null 2>&1; then json_tool=node
elif [ "$OS" != Darwin ] && command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null 2>&1; then json_tool=python3
elif [ "$OS" = Darwin ] && xcode-select -p >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then json_tool=python3
elif [ "$OS" = Darwin ] && command -v osascript >/dev/null 2>&1; then json_tool=osascript
elif command -v pwsh >/dev/null 2>&1; then json_tool=pwsh
elif command -v powershell.exe >/dev/null 2>&1; then json_tool=powershell.exe
else fail "settings.json 을 고칠 도구(jq·node·python3·osascript·PowerShell)가 하나도 없습니다"; fi

# set_statusline <settings.json> <command>: changes only .statusLine, refuses to touch a broken file
set_statusline() {
  local f=$1 c=$2 tmp="$1.tmp-$$"
  case $json_tool in
    jq)
      if [ -s "$f" ]; then jq --arg c "$c" '.statusLine = {type: "command", command: $c}' "$f" > "$tmp"
      else jq -n --arg c "$c" '{statusLine: {type: "command", command: $c}}' > "$tmp"; fi ;;
    node)
      SL_F="$f" SL_C="$c" node -e '
        const fs = require("fs"), f = process.env.SL_F;
        let s = ""; try { s = fs.readFileSync(f, "utf8"); } catch (e) {}
        const o = s.trim() ? JSON.parse(s.replace(/^﻿/, "")) : {};
        o.statusLine = { type: "command", command: process.env.SL_C };
        process.stdout.write(JSON.stringify(o, null, 2) + "\n");' > "$tmp" ;;
    python3)
      SL_F="$f" SL_C="$c" python3 -c '
import json, os, sys
f = os.environ["SL_F"]
s = open(f, encoding="utf-8-sig").read() if os.path.exists(f) else ""
o = json.loads(s) if s.strip() else {}
o["statusLine"] = {"type": "command", "command": os.environ["SL_C"]}
sys.stdout.write(json.dumps(o, indent=2, ensure_ascii=False) + "\n")' > "$tmp" ;;
    osascript)
      osascript -l JavaScript - "$f" "$c" > "$tmp" <<'JXA'
ObjC.import("Foundation");
function run(argv) {
  var s = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
  var t = s.isNil() ? "" : ObjC.unwrap(s).replace(/^﻿/, "");
  var o = t.trim() ? JSON.parse(t) : {};
  o.statusLine = { type: "command", command: argv[1] };
  return JSON.stringify(o, null, 2);
}
JXA
      ;;
    pwsh|powershell.exe)
      local wf; wf=$f; command -v cygpath >/dev/null 2>&1 && wf=$(cygpath -w "$f")
      SL_F="$wf" SL_C="$c" "$json_tool" -NoProfile -NonInteractive -Command '
        $ErrorActionPreference = "Stop"; $f = $env:SL_F
        $raw = ""; if (Test-Path -LiteralPath $f) { $raw = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8) }
        if ($raw.Trim()) { $o = $raw | ConvertFrom-Json } else { $o = [pscustomobject]@{} }
        $v = [pscustomobject]@{ type = "command"; command = $env:SL_C }
        if ($o.PSObject.Properties.Name -contains "statusLine") { $o.statusLine = $v } else { $o | Add-Member -NotePropertyName statusLine -NotePropertyValue $v }
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
        [Console]::Out.Write(($o | ConvertTo-Json -Depth 100))' > "$tmp" ;;
  esac
  local rc=$?
  if [ $rc -ne 0 ] || [ ! -s "$tmp" ] || ! grep -q '"statusLine"' "$tmp"; then
    rm -f "$tmp"; return 1
  fi
  mv -f "$tmp" "$f"
}

# 3) each config folder given (default = $CLAUDE_CONFIG_DIR or ~/.claude)
[ $# -gt 0 ] || set -- "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
sample='{"session_id":"install-check","model":{"display_name":"Claude"},"cost":{"total_duration_ms":600000},"context_window":{"used_percentage":12}}'
for dir in "$@"; do
  case $dir in "~"|"~/"*) dir="$HOME${dir#\~}";; esac
  dir=${dir%/}
  mkdir -p "$dir" || fail "폴더를 만들 수 없습니다: $dir"
  sl="$dir/statusline.sh"
  if [ -f "$sl" ] && ! cmp -s "$sl" "$TMP_SL"; then cp -p "$sl" "$sl.bak-$STAMP"; fi
  cp "$TMP_SL" "$sl" && chmod +x "$sl" 2>/dev/null

  # command written into settings.json: ~/... when under home, else the absolute path
  p=$sl
  if command -v cygpath >/dev/null 2>&1; then p=$(cygpath -m "$sl"); fi
  case $sl in "$HOME"/*) rel=${sl#"$HOME"/}; case $rel in *[!A-Za-z0-9._/-]*) cmd="bash \"$p\"";; *) cmd="bash ~/$rel";; esac;;
              *) cmd="bash \"$p\"";; esac

  st="$dir/settings.json"
  if [ -f "$st" ]; then cp -p "$st" "$st.bak-statusline-$STAMP" || fail "settings.json 사본을 못 만들었습니다: $st"; fi
  if ! set_statusline "$st" "$cmd"; then
    fail "settings.json 을 읽지 못해 그대로 두었습니다(쉼표·괄호 확인): $st"
  fi
  say "설치 끝: $dir"
  [ -f "$st.bak-statusline-$STAMP" ] && say "  예전 설정 사본: $st.bak-statusline-$STAMP"
  say "  미리보기: $(printf '%s' "$sample" | CLAUDE_CONFIG_DIR="$dir" bash "$sl")"
done
say "Claude Code 를 새로 열면 입력 칸 아래에 상태줄이 보입니다."
