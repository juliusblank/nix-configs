#!/usr/bin/env zsh
# Unit checks for the zse name helpers (no Zellij, no Claude, no network).
# Run: zsh home/modules/zse_test.zsh

emulate -L zsh
typeset -gA ZSE_REPO_SHORT=(workspace-services ws taktile-infra infra claude_code_fleet fleet nix-configs nix)
source "${0:A:h}/zse.zsh"
zmodload zsh/datetime

typeset -i fails=0
check() {
  if [[ $2 == "$3" ]]; then
    print -r "ok   $1"
  else
    print -r "FAIL $1: got '$2', want '$3'"
    ((fails++))
  fi
}

# Repo short names
check "map ws"            "$(_z_repo_short workspace-services)" ws
check "map infra"         "$(_z_repo_short taktile-infra)"      infra
check "map fleet"         "$(_z_repo_short claude_code_fleet)"  fleet
check "rule taktile-"     "$(_z_repo_short taktile-skills)"     skills
check "rule initials"     "$(_z_repo_short hackathon-athens-2026)" ha2
check "rule cut 8"        "$(_z_repo_short devshell-configs)"   devshell
check "rule short"        "$(_z_repo_short metadev)"            metadev

# Hint cleaning and the rule-based hint
check "clean"             "$(_z_hint_clean 'Cache TTL / Entity reads!')"   cache-ttl-entity
check "clean cut"         "$(_z_hint_clean 'containerization images')"     containe-images
check "rule feat:"        "$(_z_hint_rule 'feat(home): add the zse picker for sessions')" zse-picker-sessions
check "rule [ABC]"        "$(_z_hint_rule '[PCS] Fix cache TTL for entity reads')"        fix-cache-ttl
check "rule PEP:"         "$(_z_hint_rule 'PEP: make container images the default packaging')" containe-images-default
check "rule empty"        "$(_z_hint_rule '')" ""

# Names and the 40-char limit
check "name"              "$(_z_name tkt PCS-15554 cache-ttl)"          tkt-PCS-15554-cache-ttl
check "name no hint"      "$(_z_name proj platform-ha)"                 proj-platform-ha
check "name fits"         "$(_z_name rev ws-20650 retrying-backoffs-everywhe)" rev-ws-20650-retrying-backoffs-everywhe
check "name cut words"    "$(_z_name rev ws-20650 aaaaaaaaaaaa-bbbbbbbbbbbb-cccccccccccc)" rev-ws-20650-aaaaaaaaaaaa-bbbbbbbbbbbb
n=$(_z_name rev ws-20650 aaaaaaaa-bbbbbbbb-cccccccc)
check "name <= 40"        "$(( ${#n} <= 40 ))" 1
check "name keeps id"     "$(_z_name doc very-long-notion-page-title-that-goes-on-12345678 x)" doc-very-long-notion-page-title-that-goes-on-12345678

# Conversation ID (same formula as zse-claude)
check "conv id shape"     "$([[ $(_z_conv_id foo /tmp) =~ '^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-8[0-9a-f]{3}-[0-9a-f]{12}$' ]] && print 1)" 1

# Registry: keys survive _z_reg_write; _z_find / _z_resolve
ZSE_STATE_DIR=$(mktemp -d)
_z_session_state() { print none; }
_z_reg_write tkt-PCS-1-x ticket /tmp ""
_z_reg_set tkt-PCS-1-x ticket PCS-1
_z_reg_set tkt-PCS-1-x wt PCS-1
_z_reg_write tkt-PCS-1-x ticket /tmp ""
check "reg keeps keys"    "$(_z_reg_get tkt-PCS-1-x wt)"     PCS-1
check "reg one wt line"   "$(grep -c '^wt=' "$ZSE_STATE_DIR/tkt-PCS-1-x")" 1
check "find"              "$(_z_find ticket PCS-1)"          tkt-PCS-1-x
check "resolve id"        "$(_z_resolve pcs-1)"              tkt-PCS-1-x
_z_reg_write proj-plat project /tmp ""
check "resolve slug"      "$(_z_resolve plat)"               proj-plat
check "resolve exact"     "$(_z_resolve proj-plat)"          proj-plat
check "resolve none"      "$(_z_resolve nothing || print none)" none
check "worktree from reg" "$(_z_worktree_name tkt-PCS-1-x)"  PCS-1
check "worktree old rev"  "$(_z_worktree_name review-taktile-infra-pr7569)" pr-7569
check "worktree old tkt"  "$(_z_worktree_name PCS-15554)"    PCS-15554

# Shades: lowest free per colour type, stored; code-resume shares code
_z_reg_write tkt-a ticket /tmp ""
_z_reg_write tkt-b ticket /tmp ""
check "shade first"       "$(_z_shade tkt-a ticket)"         1
check "shade stored"      "$(_z_reg_get tkt-a shade)"        1
check "shade next"        "$(_z_shade tkt-b ticket)"         2
check "shade kept"        "$(_z_shade tkt-a ticket)"         1
_z_reg_set tkt-a shade ""
sed -i.bak '/^shade=$/d' "$ZSE_STATE_DIR/tkt-a"; rm -f "$ZSE_STATE_DIR/tkt-a.bak"
_z_reg_write tkt-c ticket /tmp ""
check "shade fills gap"   "$(_z_shade tkt-c ticket)"         1
check "shade other type"  "$(_z_shade proj-plat project)"    1
_z_reg_write code-x code /tmp ""
_z_reg_write code-y code-resume /tmp ""
_z_shade code-x code >/dev/null
check "shade code-resume" "$(_z_shade code-y code-resume)"   2
ZSE_SHADE_RGB=(ticket-1 '255;194;75')
check "sgr rgb"           "$(_z_sgr tkt-c ticket)"           "38;2;255;194;75"
check "sgr fallback"      "$(_z_sgr code-x code)"            "38;5;69"
check "tint mix"          "$(ZSE_TINT_PCT=50 _z_tint tkt-c ticket)" "48;2;146;115;57"
check "tint no shade rgb" "$(_z_tint code-x code)"           ""
check "tint no use case"  "$(_z_tint loose '')"              ""
check "term hex"          "$(ZSE_TERM_TINT_PCT=50 _z_term_hex tkt-c ticket)" "92/73/39"
check "term hex off"      "$(ZSE_TERM_TINT_PCT=0 _z_term_hex tkt-c ticket)" ""
check "term hex no rgb"   "$(_z_term_hex code-x code)"       ""
# Client map: the tint writes OSC 11 and remembers the session per tty
ZSE_CLIENT_DIR=$(mktemp -d)
fake_tty=$(mktemp -d)/ttys001; : >"$fake_tty"
ZSE_TERM_TINT_PCT=50 _z_tty_tint "$fake_tty" tkt-c
check "tty tint osc"      "$(<"$fake_tty")"                  $'\e]11;rgb:92/73/39\e\\'
check "tty tint map"      "$(<"$ZSE_CLIENT_DIR/ttys001")"    tkt-c
ps() { print -rl -- 'ttys001 zellij' 'ttys002 /nix/store/x/bin/zellij' '?? zellij' 'ttys003 zsh'; }
check "clients mapped"    "$(_z_client_ttys tkt-c)"          /dev/ttys001
check "clients unmapped"  "$(_z_client_ttys other | wc -l | tr -d ' ')" 0
ps() { print -rl -- 'ttys004 zellij'; }
check "clients only one"  "$(_z_client_ttys other)"          /dev/ttys004
unfunction ps
_z_tty_reset "$fake_tty"
check "tty reset map"     "$([[ -e $ZSE_CLIENT_DIR/ttys001 ]] && print kept || print gone)" gone
rm -rf "$ZSE_CLIENT_DIR" "${fake_tty:h}"
check "group review"      "$(_z_group review)"               review
check "group code-resume" "$(_z_group code-resume)"          code
check "group none"        "$(_z_group '')"                   other
rm -f "$ZSE_STATE_DIR"/(tkt-[abc]|code-[xy])

# Age
check "age bad"           "$(_z_age nonsense)" -
check "age min"           "$(_z_age "$(TZ=UTC strftime '%Y-%m-%dT%H:%M:%SZ' $((EPOCHSECONDS - 300)))")" 5m
check "age days"          "$(_z_age "$(TZ=UTC strftime '%Y-%m-%dT%H:%M:%SZ' $((EPOCHSECONDS - 200000)))")" 2d

# Activity from `claude agents --json` (stubbed)
_z_reg_write proj-plat project /work/plat ""
claude() {
  print -r -- '[
    {"name":"tkt-PCS-1-x","kind":"interactive","status":"busy","cwd":"/tmp"},
    {"name":"proj-plat","kind":"interactive","status":"idle","waitingFor":"permission","cwd":"/work/plat"},
    {"name":"","kind":"background","status":"busy","cwd":"/work/plat/.claude/worktrees/PCS-2"},
    {"name":"","kind":"background","status":"idle","cwd":"/elsewhere"},
    {"name":"code-x","kind":"interactive","status":"idle","cwd":"/tmp"}
  ]'
}
_no_timeout() { shift; "$@"; }
ZSE_TIMEOUT=_no_timeout
_z_activity_load
check "act busy"          "${ZSE_ACT[tkt-PCS-1-x]}"          busy
check "act waiting"       "${ZSE_ACT[proj-plat]}"            waiting
check "act agents"        "${ZSE_AGENTS[proj-plat]:-0}"      1
check "act word"          "$(_z_activity_word proj-plat)"    "waiting, 1 agent"
check "active busy"       "$(_z_is_active tkt-PCS-1-x && print 1)" 1
check "inactive idle"     "$(_z_is_active code-x || print 0)" 0
check "inactive unknown"  "$(_z_is_active nothing || print 0)" 0

setopt extended_glob
# Picker: groups in ZSE_GROUPS order, a separator (empty name) before each,
# rows padded to the width
zellij() { print -rl -- tkt-PCS-1-x code-x; }
_z_reg_write code-x code /tmp ""
lines=("${(@f)$(FZF_COLUMNS=83 _z_pick_lines)}")
check "pick names"        "${(j:,:)${lines[@]%%$'\t'*}}"     ",,tkt-PCS-1-x,,proj-plat,,code-x"
hdr=${${lines[1]#*$'\t'}//$'\e'\[[0-9;]#m/}
row=${${lines[3]#*$'\t'}//$'\e'\[[0-9;]#m/}
check "pick header"       "${hdr[1,11]}"                     "    SESSION"
check "pick header align" "${#${hdr%%STATE*}}"               "${#${row%%running*}}"
check "pick sep label"    "${${lines[2]#*$'\t'}//$'\e'\[[0-9;]#m/}" "tickets ${(l:72::─:)}"
plain=${${lines[5]#*$'\t'}//$'\e'\[[0-9;]#m/}
check "pick row width"    "${(m)#plain}"                     80
# The state column starts at the same place for short and long names
s1=${${lines[3]#*$'\t'}//$'\e'\[[0-9;]#m/}; s1=${s1%%running*}
s2=${${lines[7]#*$'\t'}//$'\e'\[[0-9;]#m/}; s2=${s2%%running*}
check "pick name column"  "${(m)#s1}"                        "${(m)#s2}"
unfunction zellij

# Review states (the zse-ci state file)
export XDG_CACHE_HOME=$(mktemp -d)
mkdir -p "$XDG_CACHE_HOME/zse/activity"
printf 'state=submitted\nlabel=changes requested\nauthor=theo\nat=2026-11-01T10:00:00Z\n' >"$XDG_CACHE_HOME/zse/activity/rev-a.pr"
_z_review rev-a
check "review state"      "$REPLY"                           submitted
check "review label"      "$REPLY_LABEL"                     "changes requested"
check "review badge run"  "${$(_z_review_badge rev-a 32 running)//$'\e'\[[0-9;]#m/}" "↩ changes requested"
check "review badge age"  "${${$(_z_review_badge rev-a 32 stopped)//$'\e'\[[0-9;]#m/}% · *}" "↩ changes requested"
printf 'new=2\nsummary=2 commits\n' >"$XDG_CACHE_HOME/zse/activity/rev-b.pr"
_z_review rev-b
check "review old file"   "$REPLY/$REPLY_SUMMARY"            "new/2 commits"
check "review none"       "$(_z_review rev-none || print none)" none
zellij() { print -rl -- rev-a rev-b; }
_z_reg_write rev-a review /tmp ""
_z_reg_write rev-b review /tmp ""
lines=("${(@f)$(FZF_COLUMNS=120 _z_pick_lines)}")
picked=(${lines[@]%%$'\t'*})
row_a=${(M)lines:#rev-a$'\t'*}; row_a=${${row_a#*$'\t'}//$'\e'\[[0-9;]#m/}
row_b=${(M)lines:#rev-b$'\t'*}; row_b=${${row_b#*$'\t'}//$'\e'\[[0-9;]#m/}
check "pick author"       "${${row_a#*rev-a }%% *}"          "(theo)"
check "pick author align" "${#${row_a%%running*}}"           "${#${row_b%%running*}}"
check "pick new first"    "${(j:,:)${(@M)picked:#rev-*}}"     "rev-b,rev-a"
unfunction zellij
rm -rf "$XDG_CACHE_HOME"; unset XDG_CACHE_HOME
# Review requests (#47): merge by URL, groups, review sessions by URL
ZSE_REQ_DIR=$(mktemp -d)
gh() {
  case "$*" in
    *user-review-requested*) print -r '[{"url":"https://github.com/o/r1/pull/1","repository":{"nameWithOwner":"o/r1"},"number":1,"title":"Fix A","author":{"login":"theo"},"createdAt":"2026-11-20T10:00:00Z"},{"url":"https://github.com/o/r2/pull/2","repository":{"nameWithOwner":"o/r2"},"number":2,"title":"Add B","author":{"login":"app/bot[bot]"},"createdAt":"2026-11-25T10:00:00Z"}]' ;;
    *team-review-requested*) print -r '[{"url":"https://github.com/o/r2/pull/2","repository":{"nameWithOwner":"o/r2"},"number":2,"title":"Add B","author":{"login":"app/bot[bot]"},"createdAt":"2026-11-25T10:00:00Z"},{"url":"https://github.com/o/r3/pull/3","repository":{"nameWithOwner":"o/r3"},"number":3,"title":"Team C","author":{"login":"ann"},"createdAt":"2026-11-10T10:00:00Z"}]' ;;
    *) return 1 ;;
  esac
}
_z_reg_write rev-r3-3-x review /tmp "" https://github.com/o/r3/pull/3
_z_req_fetch github
_z_req_fetch team
lines=("${(@f)$(FZF_COLUMNS=100 _z_req_lines)}")
check "req keys"          "${(j:,:)${lines[@]%%$'\t'*}}" ",,https://github.com/o/r2/pull/2,https://github.com/o/r1/pull/1,rev-r3-3-x"
plain=${${lines[3]#*$'\t'}//$'\e'\[[0-9;]#m/}
hdr=${${lines[1]#*$'\t'}//$'\e'\[[0-9;]#m/}
check "req icons"         "${plain[(w)1]} ${plain[(w)2]}"   $'\uf09b #'
check "req author column" "${plain[(w)5]}"                  "bot"
check "req header align"  "${#${hdr%%PR *}} ${#${hdr%%AUTHOR*}}" "${#${plain%%r2#2*}} ${#${plain%%bot *}}"
check "req session note"  "${${lines[5]//$'\e'\[[0-9;]#m/}#* → }" "rev-r3-3-x (Enter switches)"
locks=($ZSE_REQ_DIR/*.lock(N))
check "req no lock left"  "${#locks}" 0
ZSE_REQ_QUERY[github]='broken'
_z_req_fetch github
check "req error kept"    "$([[ -r $ZSE_REQ_DIR/github.error && -r $ZSE_REQ_DIR/github.json ]] && print 1)" 1
check "req status failed" "${${(f)$(FZF_COLUMNS=100 _z_req_lines)}[2]//$'\e'\[[0-9;]#m/}" "	requested from you ✗ failed ${$(<$ZSE_REQ_DIR/github.error)} · platform-team ✓ 0m · new commits — · Slack —"
# Score: the sum of the source weights, highest first, then oldest first
() {
  local ZSE_REQ_DIR=$(mktemp -d) n src
  _t_req() {  # FILE NUMBER AT GROUP
    ${ZSE_JQ:-jq} -nc --arg n $2 --arg at $3 --arg g $4 \
      '{url: "https://github.com/o/s/pull/\($n)", repo: "o/s", number: ($n | tonumber), title: "T\($n)", author: "a", at: $at, source: $g, group: $g}' >>"$ZSE_REQ_DIR/$1.tmp"
  }
  _t_req slack 1 2026-11-20T00:00:00Z slack            # 16
  _t_req slack 2 2026-11-21T00:00:00Z slack; _t_req github 2 2026-11-21T00:00:00Z github   # 20
  _t_req github 3 2026-11-19T00:00:00Z github; _t_req team 3 2026-11-19T00:00:00Z team; _t_req slack 3 2026-11-22T00:00:00Z linear   # 9
  _t_req github 4 2026-11-18T00:00:00Z github          # 4
  _t_req team 5 2026-11-17T00:00:00Z team              # 1
  _t_req rereview 6 2026-11-17T00:00:00Z rereview; _t_req team 6 2026-11-17T00:00:00Z team   # 3
  _t_req github 7 2026-11-17T00:00:00Z github          # 4, older than 4
  for src in slack github team rereview; do
    ${ZSE_JQ:-jq} -sc . "$ZSE_REQ_DIR/$src.tmp" >"$ZSE_REQ_DIR/$src.json"
  done
  lines=("${(@f)$(FZF_COLUMNS=100 _z_req_lines)}")
  local -a keys=("${(@)${(@)lines[3,-1]%%$'\t'*}##*/}")
  check "req score order" "${(j:,:)keys}" "2,1,3,7,4,6,5"
  rm -rf "$ZSE_REQ_DIR"
  unfunction _t_req
}
# Slack and Linear: zse reads the raw tool results (stream-json) and finds
# the links itself; own and bot messages, other channels, closed and old
# PRs drop; SH requests only during a shift; Linear PRs by exact title.
_t_n=0
# _t_call NAME INPUT-JSON RESULT-TEXT — one tool call and its result
_t_call() {
  ((++_t_n))
  ${ZSE_JQ:-jq} -nc --arg id t$_t_n --arg name $1 --argjson input $2 \
    '{type: "assistant", message: {content: [{type: "tool_use", id: $id, name: $name, input: $input}]}}'
  ${ZSE_JQ:-jq} -nc --arg id t$_t_n --arg text $3 \
    '{type: "user", message: {content: [{type: "tool_result", tool_use_id: $id, content: [{type: "text", text: $text}]}]}}'
}
# _t_msg CHANNEL FROM-NAME FROM-ID TIME TEXT [BOT] — one search result
_t_msg() {
  print -r -- "Channel: $1 (ID: C1)
From: $2 <x@example.com> (ID: $3) ${6:+ [BOT]}
Time: $4
Message_ts: $(${ZSE_JQ:-jq} -nr --arg t $4 '$t | fromdate').000100
Permalink: [link](https://example.slack.com/archives/C1/p1)
Text: 
> $5
Context after: 
- From: Zed (ID: U9) 
  > not this one <https://github.com/o/r99/pull/99|ctx>
"
}
# _t_search QUERY CURSOR PAGINATION MSG… — a Slack search call
_t_search() {
  local q=$1 c=$2 pag=$3 body="# Search Results for: $1" i=0 input
  shift 3
  for m; do body+=$'\n### Result '"$((++i)) of $#"$'\n'"$m"$'\n---\n'; done
  input=$(${ZSE_JQ:-jq} -nc --arg q "$q" --arg c "$c" '{query: $q} + (if $c == "" then {} else {cursor: $c} end)')
  _t_call mcp__claude_ai_Slack__slack_search_public_and_private "$input" \
    "$(${ZSE_JQ:-jq} -nc --arg r "$body" --arg p "$pag" '{results: $r, pagination_info: $p}')"
}
_t_stream() {
  local end='End of results - No more pages available.' w="after:$(TZ=UTC strftime '%Y-%m-%d' $((EPOCHSECONDS - 8 * 86400)))"
  _t_call mcp__claude_ai_Slack__slack_read_user_profile '{}' $'User ID: U1\nUsername: me'
  _t_search "is:dm github.com/ pull $w" "" 'For the next page of results use cursor `C2`' \
    "$(_t_msg DM Theo U2 2026-11-26T10:00:00Z 'stamp? <https://github.com/o/r1/pull/1/files#diff|github.com/o/r1/pull/1/files>')" \
    "$(_t_msg DM Me U1 2026-11-26T10:00:00Z 'mine <https://github.com/o/r11/pull/11|x>')" \
    "$(_t_msg DM Claudius U3 2026-11-26T10:00:00Z 'digest <https://github.com/o/r12/pull/12|x>' bot)"
  _t_search "is:dm github.com/ pull $w" C2 "$end" \
    "$(_t_msg DM Bo U4 2026-11-25T10:00:00Z 'closed one <https://github.com/o/r5/pull/5|x>')" \
    "$(_t_msg DM Bot U5 2026-11-25T10:00:00Z 'my own <https://github.com/o/r7/pull/7|x>')" \
    "$(_t_msg DM Cy U6 $old_iso 'old <https://github.com/o/r6/pull/6|x>')" \
    "$(_t_msg DM Gab U7 2026-11-26T15:30:57Z 'small PRs
> • <https://github.com/o/ws/pull/31|a>
> • <https://github.com/o/ws/pull/26/changes|b>
> • <https://github.com/o/ws/pull/32/changes#diff-b2|c> and <https://github.com/o/ws/issues/9|d>')"
  _t_search "to:me github.com/ pull $w" "" "$end"
  _t_search "@me github.com/ pull $w" "" "$end" \
    "$(_t_msg '#proj-x' Ann U8 2026-11-25T10:00:00Z 'review please <@U1|me> <https://github.com/o/r4/pull/4|x>')" \
    "$(_t_msg '#proj-y' Ann U8 2026-11-25T10:00:00Z 'group mention <!subteam^S1> <https://github.com/o/r13/pull/13|x>')"
  _t_search "in:#team-platform github.com/ pull $w" "" "$end" \
    "$(_t_msg '#team-platform' Dan U10 2026-11-24T10:00:00Z 'SH: review? <https://github.com/o/r8/pull/8|x>')" \
    "$(_t_msg '#team-platform' Eve U11 2026-11-25T10:00:00Z 'SH: not my shift <https://github.com/o/r9/pull/9|x>')"
  _t_call mcp__claude_ai_Linear__get_notifications '{"limit":50}' '{"notifications":[
    {"type":"pullRequestReviewRequested","title":"Ten","subtitle":"Katia Recard requested your review","createdAt":"2026-11-23T10:00:00.000Z","archivedAt":null},
    {"type":"pullRequestReviewRequested","title":"Gone","subtitle":"Katia Recard requested your review","createdAt":"2026-11-23T10:00:00.000Z","archivedAt":"2026-11-24T10:00:00.000Z"},
    {"type":"issueNewComment","title":"Eleven","subtitle":"Katia Recard commented","createdAt":"2026-11-23T10:00:00.000Z","archivedAt":null}],"hasNextPage":false}'
}
now_iso=$(TZ=UTC strftime '%Y-%m-%dT%H:%M:%SZ' $EPOCHSECONDS)
old_iso=$(TZ=UTC strftime '%Y-%m-%dT%H:%M:%SZ' $((EPOCHSECONDS - 9 * 86400)))
claude() {
  if [[ $* == *schedule_show* ]]; then
    print -r -- x >>"$ZSE_REQ_DIR/shift-calls"
    print -r -- '{"me":"U1","shifts":[{"user_id":"U1","start_at":"2026-11-24T00:00:00Z","end_at":"2026-11-25T00:00:00Z"},{"user_id":"U2","start_at":"2026-11-25T00:00:00Z","end_at":"2026-11-26T00:00:00Z"}]}'
    return
  fi
  print -r -- "$*" >"$ZSE_REQ_DIR/prompt"
  _t_stream
}
gh() {
  [[ $1 == api ]] || return 1
  if [[ $* == *'s1: search('* ]]; then
    print -r -- '{"data":{"s1":{"nodes":[{"url":"https://github.com/o/r10/pull/10","title":"Ten"},{"url":"https://github.com/o/r14/pull/14","title":"Ten more"}]}}}'
    return
  fi
  print -r -- '{"data":{"viewer":{"login":"me"},
    "p1":{"pullRequest":{"url":"https://github.com/o/r1/pull/1","title":"Fix A","state":"OPEN","author":{"login":"theo"},"reviews":{"nodes":[{"author":{"login":"me"},"submittedAt":"2026-11-26T12:00:00Z"}]}}},
    "p2":{"pullRequest":{"url":"https://github.com/o/r4/pull/4","title":"Four","state":"OPEN","author":{"login":"ann"},"reviews":{"nodes":[]}}},
    "p3":{"pullRequest":{"url":"https://github.com/o/r5/pull/5","title":"Five","state":"CLOSED","author":{"login":"bo"},"reviews":{"nodes":[]}}},
    "p4":{"pullRequest":{"url":"https://github.com/o/r6/pull/6","title":"Six","state":"OPEN","author":{"login":"cy"},"reviews":{"nodes":[]}}},
    "p5":{"pullRequest":{"url":"https://github.com/o/r7/pull/7","title":"Mine","state":"OPEN","author":{"login":"me"},"reviews":{"nodes":[]}}},
    "p6":{"pullRequest":{"url":"https://github.com/o/r8/pull/8","title":"Eight","state":"OPEN","author":{"login":"dan"},"reviews":{"nodes":[]}}},
    "p7":{"pullRequest":{"url":"https://github.com/o/r9/pull/9","title":"Nine","state":"OPEN","author":{"login":"eve"},"reviews":{"nodes":[]}}},
    "p8":{"pullRequest":{"url":"https://github.com/o/r10/pull/10","title":"Ten","state":"OPEN","author":{"login":"katia-recard-taktile"},"reviews":{"nodes":[]}}}}}'
}
parsed=$(_t_stream | _z_req_slack_parse)
check "slack parse error" "$(print -r -- "$parsed" | ${ZSE_JQ:-jq} -r '.error')" null
check "slack parse urls"  "$(print -r -- "$parsed" | ${ZSE_JQ:-jq} -r '[.items[] | "\(.url | sub(".*github.com/"; "")) \(.via)"] | join(",")')" "o/r1/pull/1 dm,o/r4/pull/4 @,o/r5/pull/5 dm,o/r6/pull/6 dm,o/r7/pull/7 dm,o/r8/pull/8 sh,o/r9/pull/9 sh,o/ws/pull/26 dm,o/ws/pull/31 dm,o/ws/pull/32 dm"
check "slack parse text"  "$(print -r -- "$parsed" | ${ZSE_JQ:-jq} -r '.items[0].text')" "stamp? https://github.com/o/r1/pull/1/files#diff"
check "slack parse at"    "$(print -r -- "$parsed" | ${ZSE_JQ:-jq} -r '.items[0].at')" 2026-11-26T10:00:00Z
check "linear parse"      "$(print -r -- "$parsed" | ${ZSE_JQ:-jq} -c '[.linear[] | [.title, .from]]')" '[["Ten","Katia Recard"]]'
check "slack page missing" "$(_t_stream | ${ZSE_JQ:-jq} -c 'select(.message.content[0].input.cursor? != "C2")' | _z_req_slack_parse | ${ZSE_JQ:-jq} -r .error)" "1 Slack result pages not fetched"
check "slack query missing" "$(_t_stream | ${ZSE_JQ:-jq} -c 'select((.message.content[0].input.query? // "") | startswith("to:me") | not)' | _z_req_slack_parse | ${ZSE_JQ:-jq} -r .error)" "missing searches: to:me "
rm -f "$ZSE_REQ_DIR"/*.json(N) "$ZSE_REQ_DIR"/*.error(N)
_z_req_fetch slack
check "slack urls"        "$(${ZSE_JQ:-jq} -r '[.[].url] | join(",")' "$ZSE_REQ_DIR/slack.json")" "https://github.com/o/r1/pull/1,https://github.com/o/r10/pull/10,https://github.com/o/r4/pull/4,https://github.com/o/r8/pull/8"
check "slack shifts"      "$(${ZSE_JQ:-jq} -c . "$ZSE_REQ_DIR/shifts.json")" '[{"start":"2026-11-24T00:00:00","end":"2026-11-25T00:00:00"}]'
check "slack window"      "$([[ $(<$ZSE_REQ_DIR/prompt) =~ 'after:([0-9-]+)' ]] && print $match[1])" "$(TZ=UTC strftime '%Y-%m-%d' $((EPOCHSECONDS - 8 * 86400)))"
check "slack last search" "$(( $(<$ZSE_REQ_DIR/last-slack-search) >= EPOCHSECONDS - 5 ))" 1
lines=("${(@f)$(FZF_COLUMNS=100 _z_req_lines)}")
check "slack keys"        "${(j:,:)${lines[@]%%$'\t'*}}" ",,https://github.com/o/r8/pull/8,https://github.com/o/r4/pull/4,https://github.com/o/r1/pull/1,https://github.com/o/r10/pull/10"
plain=${${lines[6]#*$'\t'}//$'\e'\[[0-9;]#m/}
check "linear icon"       "${plain[(w)1]}"                  $'\U000f0c0d'
check "linear author"     "${plain[(w)4]}"                  "katia"
check "slack icon"        "${${${lines[3]#*$'\t'}//$'\e'\[[0-9;]#m/}[(w)1]}" $''
plain=${${lines[5]#*$'\t'}//$'\e'\[[0-9;]#m/}
check "slack reviewed"    "${plain##*reviewed }"            "$(_z_age 2026-11-26T12:00:00Z) ago"
check "slack preview via" "$(_z_pick_preview https://github.com/o/r4/pull/4 | head -n 1)" "@ · Ann · 2026-11-25 10:00: review please <@U1|me> https://github.com/o/r4/pull/4"
# A failed search keeps the earlier entries and gives the reason
claude() { _t_stream | ${ZSE_JQ:-jq} -c 'select((.message.content[0].input.query? // "") | startswith("to:me") | not)'; }
_z_req_fetch slack
check "slack keeps old"   "$(${ZSE_JQ:-jq} length "$ZSE_REQ_DIR/slack.json")" 4
check "slack why"         "$(<$ZSE_REQ_DIR/slack.why)" "missing searches: to:me "
check "shifts once a day" "$(wc -l <"$ZSE_REQ_DIR/shift-calls" | tr -d ' ')" 1
claude() { print ERROR; }
_z_req_fetch slack
check "slack error"       "$([[ -r $ZSE_REQ_DIR/slack.error ]] && ${ZSE_JQ:-jq} length "$ZSE_REQ_DIR/slack.json")" 4
# New commits since my review: kept only with a commit after my latest
# review; a row from this source alone is hidden when a session exists.
rm -f "$ZSE_REQ_DIR"/*.json(N) "$ZSE_REQ_DIR"/*.error(N)
gh() {
  [[ $* == *reviewed-by* ]] || return 1
  print -r -- '{"data":{"viewer":{"login":"me"},"search":{"nodes":[
    {"url":"https://github.com/o/r11/pull/11","number":11,"title":"Eleven","repository":{"nameWithOwner":"o/r11"},"author":{"login":"ann"},
     "commits":{"nodes":[{"commit":{"committedDate":"2026-11-26T10:00:00Z"}}]},"reviews":{"nodes":[{"author":{"login":"me"},"submittedAt":"2026-11-25T10:00:00Z"}]}},
    {"url":"https://github.com/o/r12/pull/12","number":12,"title":"Twelve","repository":{"nameWithOwner":"o/r12"},"author":{"login":"bo"},
     "commits":{"nodes":[{"commit":{"committedDate":"2026-11-24T10:00:00Z"}}]},"reviews":{"nodes":[{"author":{"login":"me"},"submittedAt":"2026-11-25T10:00:00Z"}]}},
    {"url":"https://github.com/o/r13/pull/13","number":13,"title":"Thirteen","repository":{"nameWithOwner":"o/r13"},"author":{"login":"cy"},
     "commits":{"nodes":[{"commit":{"committedDate":"2026-11-26T10:00:00Z"}}]},"reviews":{"nodes":[{"author":{"login":"me"},"submittedAt":"2026-11-25T10:00:00Z"}]}}]}}}'
}
_z_req_fetch rereview
check "rereview urls"     "$(${ZSE_JQ:-jq} -r '[.[].url] | join(",")' "$ZSE_REQ_DIR/rereview.json")" "https://github.com/o/r11/pull/11,https://github.com/o/r13/pull/13"
_z_reg_write rev-r13-13-x review /tmp "" https://github.com/o/r13/pull/13
lines=("${(@f)$(FZF_COLUMNS=100 _z_req_lines)}")
check "rereview no sess"  "${(j:,:)${lines[@]%%$'\t'*}}"  ",,https://github.com/o/r11/pull/11"
rm -f "$ZSE_STATE_DIR/rev-r13-13-x"
unfunction gh
rm -rf "$ZSE_REQ_DIR" "$ZSE_STATE_DIR/rev-r3-3-x"
unfunction claude
rm -rf "$ZSE_STATE_DIR"

print
((fails)) && { print -r "$fails check(s) failed"; exit 1; }
print -r "all checks passed"
