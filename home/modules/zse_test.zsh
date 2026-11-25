#!/usr/bin/env zsh
# Unit checks for the zse name helpers (no Zellij, no Claude, no network).
# Run: zsh home/modules/zse_test.zsh

emulate -L zsh
typeset -gA ZSE_REPO_SHORT=(workspace-services ws taktile-infra infra claude_code_fleet fleet nix-configs nix)
source "${0:A:h}/zse.zsh"

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
rm -rf "$ZSE_STATE_DIR"

print
((fails)) && { print -r "$fails check(s) failed"; exit 1; }
print -r "all checks passed"
