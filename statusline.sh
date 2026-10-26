#!/usr/bin/env bash
# Claude Code status line (the line under the chat box).
#   🕐 last activity | session minutes | model | context % | 5h % (time to reset) | weekly % | account | $cost
# Pure bash builtins on the hot path (no cat/sed/grep per render), so it stays fast even on busy
# Windows (Git Bash) machines. Works on bash 3.2 (macOS /bin/bash) and newer.
# https://github.com/Raidcompany/claude-statusline  (MIT)
EPOCH=${EPOCHSECONDS:-}
[[ $EPOCH =~ ^[0-9]+$ ]] || EPOCH=$(date +%s)
IFS= read -r -d '' input || :
input=${input%"${input##*[!$'\n']}"}
flat=${input//$'\n'/}

# If Orca is installed, hand the same input to its own status line hook so Orca's usage bars keep
# working. Runs in the background, at most once per 15 seconds, output ignored.
ORCA_HOOK="$HOME/.orca/agent-hooks/claude-statusline.sh"
ORCA_RUN=sh
if [ ! -f "$ORCA_HOOK" ]; then
  ORCA_HOOK=; ORCA_RUN=
  case $OSTYPE in msys*|cygwin*) [ -f "$HOME/.orca/agent-hooks/claude-statusline.cmd" ] && ORCA_HOOK="$HOME/.orca/agent-hooks/claude-statusline.cmd";; esac
fi
if [ -n "$ORCA_HOOK" ] && [ -z "$CLAUDE_JOB_DIR" ] && [ -n "$ORCA_PANE_KEY" ] && [[ $flat == *'"rate_limits"'* ]]; then
  orca_pk=${ORCA_PANE_KEY: -36}; orca_pk=${orca_pk//:/_}
  orca_stamp="${TEMP:-/tmp}/cc-statusline-orca-last-$orca_pk.txt"
  orca_last=0; [ -f "$orca_stamp" ] && { read -r orca_last < "$orca_stamp"; } 2>/dev/null
  [[ $orca_last =~ ^[0-9]+$ ]] || orca_last=0
  if (( EPOCH - orca_last >= 15 || EPOCH < orca_last )); then
    printf '%s' "$EPOCH" > "$orca_stamp" 2>/dev/null
    orca_tmp="${TEMP:-/tmp}/cc-statusline-$$.json"
    printf '%s' "$input" > "$orca_tmp"
    { $ORCA_RUN "$ORCA_HOOK" < "$orca_tmp" >/dev/null 2>&1; rm -f "$orca_tmp"; } </dev/null >/dev/null 2>&1 &
  fi
fi

# --- model (model.display_name) ---
model=""
re_model_block='"model"[[:space:]]*:[[:space:]]*\{[^{}]*\}'
re_display='"display_name"[[:space:]]*:[[:space:]]*"([^"]*)"'
if [[ $flat =~ $re_model_block ]]; then
  model_block=${BASH_REMATCH[0]}
  [[ $model_block =~ $re_display ]] && model=${BASH_REMATCH[1]}
fi

# --- session length (cost.total_duration_ms; skipped if absent) ---
ms=""
re_ms='"total_duration_ms"[[:space:]]*:[[:space:]]*([0-9]+)'
[[ $flat =~ $re_ms ]] && ms=${BASH_REMATCH[1]}

now=""
printf -v now '%(%H:%M)T' -1 2>/dev/null
[ -z "$now" ] && now=$(date +%H:%M)

out="🕐 마지막 활동 $now"
[ -n "$ms" ] && out="$out | 세션 $((ms / 60000))분"
[ -n "$model" ] && out="$out | $model"

# --- context window (context_window.used_percentage) ---
ctx_pct=""
re_cw='"context_window"[[:space:]]*:[[:space:]]*\{([^{}]|\{[^{}]*\})*\}'
re_pct='"used_percentage"[[:space:]]*:[[:space:]]*([0-9]+(\.[0-9]+)?)'
if [[ $flat =~ $re_cw ]]; then
  cw_block=${BASH_REMATCH[0]}
  [[ $cw_block =~ $re_pct ]] && ctx_pct=${BASH_REMATCH[1]}
fi
[ -n "$ctx_pct" ] && { printf -v n '%.0f' "$ctx_pct"; out="$out | 컨텍스트 $n%"; }

re_sid='"session_id"[[:space:]]*:[[:space:]]*"([^"]+)"'
sid=""; [[ $flat =~ $re_sid ]] && sid=${BASH_REMATCH[1]}

# --- usage limits (rate_limits.five_hour / seven_day: used_percentage, resets_at = unix seconds) ---
# Time left until reset is shown in brackets: 3일4시간 · 2시간13분 · 7분.
re_reset='"resets_at"[[:space:]]*:[[:space:]]*([0-9]+)'
left_txt() {  # $1 = resets_at -> sets global "left" to '(...)' or ""
  left=""
  [[ $1 =~ ^[0-9]+$ ]] || return 0
  local s=$(( $1 - EPOCH )) d h m
  (( s > 0 )) || return 0
  d=$(( s / 86400 )); h=$(( s % 86400 / 3600 )); m=$(( (s % 3600 + 59) / 60 ))
  (( m == 60 )) && { m=0; h=$(( h + 1 )); }
  (( h == 24 )) && { h=0; d=$(( d + 1 )); }
  if (( d > 0 )); then left="(${d}일${h}시간)"
  elif (( h > 0 )); then left="(${h}시간${m}분)"
  else left="(${m}분)"
  fi
}
five_pct="" five_reset="" five_block=""
re_five='"five_hour"[[:space:]]*:[[:space:]]*\{[^{}]*\}'
if [[ $flat =~ $re_five ]]; then
  five_block=${BASH_REMATCH[0]}
  [[ $five_block =~ $re_pct ]] && five_pct=${BASH_REMATCH[1]}
  [[ $five_block =~ $re_reset ]] && five_reset=${BASH_REMATCH[1]}
fi
[ -n "$five_pct" ] && { printf -v n '%.0f' "$five_pct"; left_txt "$five_reset"; out="$out | 5h $n%$left"; }

week_pct="" week_reset="" week_block=""
re_week='"seven_day"[[:space:]]*:[[:space:]]*\{[^{}]*\}'
if [[ $flat =~ $re_week ]]; then
  week_block=${BASH_REMATCH[0]}
  [[ $week_block =~ $re_pct ]] && week_pct=${BASH_REMATCH[1]}
  [[ $week_block =~ $re_reset ]] && week_reset=${BASH_REMATCH[1]}
fi
[ -n "$week_pct" ] && { printf -v n '%.0f' "$week_pct"; left_txt "$week_reset"; out="$out | 주간 $n%$left"; }

# --- which account this tab is using (shown only when it can be read) ---
# Token = CLAUDE_CODE_OAUTH_TOKEN env, else env.CLAUDE_CODE_OAUTH_TOKEN in <config dir>/settings(.local).json,
# else <config dir>/.credentials.json (Windows/Linux; macOS keeps it in the Keychain, which is not read).
# Owner = the part before @ of account.email from api.anthropic.com/api/oauth/profile.
# The token never goes to the screen, a file or a command line (curl reads the header from stdin);
# the cache is keyed by the first 12 hex chars of its sha256. Cache: 1 hour per token, 5 minutes per session.
acct_who=""
acct_resolve() {
  { set +x; } 2>/dev/null
  local tok="" f c fp at name body code resp
  local sd="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" sn sc
  if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then tok=$CLAUDE_CODE_OAUTH_TOKEN
  else
    local re_senv='"env"[[:space:]]*:[[:space:]]*\{[^{}]*"CLAUDE_CODE_OAUTH_TOKEN"[[:space:]]*:[[:space:]]*"([^"]+)"'
    for sn in settings.json settings.local.json; do
      sc=""; [ -f "$sd/$sn" ] && { IFS= read -r -d '' sc < "$sd/$sn" || :; }
      shopt -s nocasematch
      [[ ${sc//$'\n'/} =~ $re_senv ]] && tok=${BASH_REMATCH[1]}
      shopt -u nocasematch
      sc=""
      [ -n "$tok" ] && break
    done
  fi
  if [ -z "$tok" ]; then
    f="$sd/.credentials.json"
    [ -f "$f" ] && { IFS= read -r -d '' c < "$f" || :; }
    local re_tok='"claudeAiOauth"[[:space:]]*:[[:space:]]*\{[^{}]*"accessToken"[[:space:]]*:[[:space:]]*"([^"]+)"'
    [[ ${c//$'\n'/} =~ $re_tok ]] && tok=${BASH_REMATCH[1]}
    c=""
  fi
  [ -n "$tok" ] || return 0
  local shacmd
  if command -v sha256sum >/dev/null 2>&1; then shacmd="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then shacmd="shasum -a 256"
  else return 0; fi
  local fpf; fpf=$(printf '%s' "$tok" | $shacmd); fp=${fpf:0:12}
  [[ $fp =~ ^[0-9a-f]{12}$ ]] || return 0
  local cd="$HOME/.claude/statusline-cache"; [ -d "$cd" ] || mkdir -p "$cd" 2>/dev/null
  if [ -f "$cd/$fp.txt" ] && read -r at name < "$cd/$fp.txt" && [[ $at =~ ^[0-9]+$ ]] && (( EPOCH - at < 3600 && EPOCH >= at )); then
    [ "$name" = - ] || acct_who=$name
    return 0
  fi
  command -v curl >/dev/null 2>&1 || return 0
  resp=$(printf 'header = "Authorization: Bearer %s"\nheader = "anthropic-beta: oauth-2025-04-20"\n' "$tok" \
    | curl -q -sS -m 5 --retry 0 -K - -w '\n%{http_code}' https://api.anthropic.com/api/oauth/profile 2>/dev/null)
  tok=""
  code=${resp##*$'\n'}; body=${resp%$'\n'*}; body=${body//$'\n'/}
  local re_mail='"account"[[:space:]]*:[[:space:]]*\{[^{}]*"email(_address)?"[[:space:]]*:[[:space:]]*"([^"@]+)@'
  if [ "$code" = 401 ]; then name="만료토큰"
  elif [ "$code" = 200 ] && [[ $body =~ $re_mail ]]; then name=${BASH_REMATCH[2]//[^A-Za-z0-9._-]/}
  elif [ "$code" = 403 ]; then name=-   # token without profile scope (e.g. setup-token): remember, don't ask for 1 hour
  else return 0; fi                     # network error: try again in 5 minutes
  [ -n "$name" ] || return 0
  printf '%s %s\n' "$EPOCH" "$name" > "$cd/$fp.$$.tmp" 2>/dev/null && mv -f "$cd/$fp.$$.tmp" "$cd/$fp.txt" 2>/dev/null
  [ "$name" = - ] || acct_who=$name
}
if [ -n "$sid" ]; then
  acct_mark="${TEMP:-/tmp}/cc-statusline-acct-${sid//[^A-Za-z0-9-]/}-${PPID:-0}.txt"
  acct_at=""
  [ -f "$acct_mark" ] && { read -r acct_at acct_who < "$acct_mark"; } 2>/dev/null
  if ! [[ $acct_at =~ ^[0-9]+$ ]] || (( EPOCH - acct_at >= 300 || EPOCH < acct_at )); then
    acct_who=""
    acct_resolve 2>/dev/null
    printf '%s %s\n' "$EPOCH" "${acct_who:--}" > "$acct_mark" 2>/dev/null
  fi
  [ "$acct_who" = - ] && acct_who=""
fi
[ -n "$acct_who" ] && out="$out | 계정 $acct_who"

# --- session cost (cost.total_cost_usd; hidden when 0, e.g. on a subscription plan) ---
cost=""
re_cost='"total_cost_usd"[[:space:]]*:[[:space:]]*([0-9]+(\.[0-9]+)?)'
[[ $flat =~ $re_cost ]] && cost=${BASH_REMATCH[1]}
if [ -n "$cost" ] && [[ $cost != 0 && ! $cost =~ ^0\.0+$ ]]; then
  printf -v n '%.2f' "$cost"; out="$out | \$$n"
fi

printf '%s' "$out"
