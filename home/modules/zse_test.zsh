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
check "pick names"        "${(j:,:)${lines[@]%%$'\t'*}}"     ",tkt-PCS-1-x,,proj-plat,,code-x"
check "pick sep label"    "${${lines[1]#*$'\t'}//$'\e'\[[0-9;]#m/}" "tickets ${(l:72::─:)}"
plain=${${lines[4]#*$'\t'}//$'\e'\[[0-9;]#m/}
check "pick row width"    "${(m)#plain}"                     80
# The state column starts at the same place for short and long names
s1=${${lines[2]#*$'\t'}//$'\e'\[[0-9;]#m/}; s1=${s1%%running*}
s2=${${lines[6]#*$'\t'}//$'\e'\[[0-9;]#m/}; s2=${s2%%running*}
check "pick name column"  "${(m)#s1}"                        "${(m)#s2}"
unfunction zellij

# Review states (the zse-ci state file)
export XDG_CACHE_HOME=$(mktemp -d)
mkdir -p "$XDG_CACHE_HOME/zse/activity"
printf 'state=submitted\nlabel=changes requested\nat=2026-11-01T10:00:00Z\n' >"$XDG_CACHE_HOME/zse/activity/rev-a.pr"
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
check "pick new first"    "${(j:,:)${(@M)picked:#rev-*}}"     "rev-b,rev-a"
unfunction zellij
rm -rf "$XDG_CACHE_HOME"; unset XDG_CACHE_HOME
unfunction claude
rm -rf "$ZSE_STATE_DIR"

print
((fails)) && { print -r "$fails check(s) failed"; exit 1; }
print -r "all checks passed"
