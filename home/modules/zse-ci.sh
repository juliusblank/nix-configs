# zse-ci — the review status pane of the `review` layout (roadmap #44).
#
# Plain bash, run by the `zse-ci` wrapper in zellij.nix, which sets:
#   ZSE_META   zse-meta (session keys: pr, owner, repo)
#   ZSE_CI_JQ  zse-ci.jq (gh JSON → summary)
#   JQ, TIMEOUT
#
# Every $ZSE_CI_INTERVAL seconds (default 30), from `gh` only (HTTPS, no SSH,
# no Claude): PR state, review decision, mergeable state, CI summary, and
# what is new since my last review or comment (commits, reviews and comments
# by others). Something new: highlighted here, ` ✱` on the tab name, and
# ~/.cache/zse/activity/<session>.pr for the zse picker. My next review or
# comment clears it.
#
# Keys: r refresh, t ticket status (Linear, through `claude -p`), q quit.

set -uo pipefail

session=${ZELLIJ_SESSION_NAME:-}
pr=$("$ZSE_META" pr)
if [[ -z $pr ]]; then
  echo "zse-ci: no PR number for session '$session'"
  exec zsh
fi
owner=$("$ZSE_META" owner)
repo=$("$ZSE_META" repo)
repo_args=()
[[ -n $owner && -n $repo ]] && repo_args=(-R "$owner/$repo")
interval=${ZSE_CI_INTERVAL:-30}
state_file="${XDG_CACHE_HOME:-$HOME/.cache}/zse/activity/$session.pr"
mkdir -p "${state_file%/*}"

bold=$'\e[1m' dim=$'\e[2m' red=$'\e[31m' green=$'\e[32m' yellow=$'\e[33m'
hl=$'\e[1;30;43m' reset=$'\e[0m'

me=$(gh api user -q .login 2>/dev/null)
ticket_line=""

# This pane's tab ID (rename-tab-by-id works in background sessions too).
tab_id=$(zellij action list-panes --tab --json 2>/dev/null \
  | "$JQ" -r --arg id "${ZELLIJ_PANE_ID:-}" \
    '.[] | select((.is_plugin | not) and ((.id | tostring) == $id)) | .tab_id' | head -n 1)

# set_badge on|off — add or remove " ✱" at the end of the tab name.
set_badge() {
  [[ -n $tab_id ]] || return 0
  local name want
  name=$(zellij action list-tabs --json 2>/dev/null \
    | "$JQ" -r --argjson id "$tab_id" '.[] | select(.tab_id == $id) | .name')
  [[ -n $name ]] || return 0
  want=${name% ✱}
  [[ $1 == on ]] && want="$want ✱"
  [[ $want == "$name" ]] || zellij action rename-tab-by-id "$tab_id" "$want" >/dev/null 2>&1
}

# ticket_status ID — one line from Linear, through `claude -p` (Haiku) with
# only the Linear connector's get_issue; run in $HOME without the pane's
# session markers.
ticket_status() {
  (
    cd "$HOME" || exit 1
    unset DELIVERY_SESSION ZSE_USE_CASE CLAUDECODE CLAUDE_CODE_ENTRYPOINT \
      CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION
    "$TIMEOUT" 45 claude -p --model haiku --allowedTools mcp__claude_ai_Linear__get_issue \
      --output-format text \
      "Read Linear issue $1 with the get_issue tool. Reply with exactly one line and nothing else: <status> · <assignee or unassigned> · <title>. If you cannot read the issue, reply ERROR." \
      </dev/null 2>/dev/null | head -n 1
  )
}

render() {
  local json s
  if ! json=$(gh pr view "$pr" "${repo_args[@]}" --json \
    title,state,isDraft,reviewDecision,mergeable,headRefName,headRefOid,commits,reviews,comments,statusCheckRollup 2>&1); then
    clear
    printf 'PR #%s\n%s\n\n%s · every %ss · r refresh · q quit\n' "$pr" "$json" "$(date '+%H:%M:%S')" "$interval"
    return
  fi
  if ! s=$(printf '%s' "$json" | "$JQ" --arg me "$me" -f "$ZSE_CI_JQ" 2>&1); then
    clear
    printf 'zse-ci: cannot read the PR data: %s\n' "$s"
    return
  fi
  q() { printf '%s' "$s" | "$JQ" -r "$1"; }

  local title state draft decision mergeable new
  title=$(q .title)
  state=$(q .state)
  draft=$(q .draft)
  decision=$(q '.decision | ascii_downcase | gsub("_"; " ")')
  mergeable=$(q '.mergeable | ascii_downcase')
  new=$(q .new)
  branch=$(q .branch)

  clear
  printf '%sPR #%s%s  %s\n' "$bold" "$pr" "$reset" "$title"
  local status_line="$state"
  [[ $draft == true ]] && status_line+=" · draft"
  [[ -n $decision ]] && status_line+=" · $decision"
  [[ -n $mergeable && $mergeable != unknown ]] && status_line+=" · $mergeable"
  printf '%s%s%s\n' "$dim" "$status_line" "$reset"

  # CI
  local pass fail pending skip
  pass=$(q .ci.pass) fail=$(q .ci.fail) pending=$(q .ci.pending) skip=$(q .ci.skip)
  printf 'CI  %s✓ %s%s' "$green" "$pass" "$reset"
  ((fail)) && printf '  %s✗ %s%s' "$red" "$fail" "$reset"
  ((pending)) && printf '  %s… %s%s' "$yellow" "$pending" "$reset"
  ((skip)) && printf '  %sskipped %s%s' "$dim" "$skip" "$reset"
  printf '\n'
  ((fail)) && q '.ci.failing[] | "    ✗ " + .' | sed "s/^/$red/;s/\$/$reset/"
  ((pending)) && q '.ci.running[0:3][] | "    … " + .'
  printf '\n'

  # Since my last review / comment
  if [[ $(q '.base == null') == true ]]; then
    printf '%sYou have not reviewed or commented yet.%s\n' "$dim" "$reset"
    rm -f "$state_file"
    set_badge off
  elif ((new)); then
    local nc no
    nc=$(q '.new_commits | length')
    no=$(q '.new_others | length')
    printf '%s ✱ new since your %s (%s UTC): ' "$hl" "$(q .base.kind)" "$(q .base.at)"
    local parts=()
    ((nc)) && parts+=("$nc commit$( ((nc > 1)) && echo s)")
    ((no)) && parts+=("$no by others")
    printf '%s %s\n' "$(IFS=,; echo "${parts[*]}" | sed 's/,/, /g')" "$reset"
    q '.new_commits[-5:][] | "  + " + .oid + " " + .line'
    ((nc > 5)) && printf '  … %s more\n' "$((nc - 5))"
    q '.new_others[-3:][] | "  @" + .author + " (" + .kind + ", " + .at + "): " + .line'
    {
      printf 'new=%s\n' "$new"
      printf 'summary=%s\n' "$(IFS=,; echo "${parts[*]}" | sed 's/,/, /g')"
    } >"$state_file"
    set_badge on
  else
    printf '%s✓ nothing new since your %s (%s UTC)%s\n' "$green" "$(q .base.kind)" "$(q .base.at)" "$reset"
    rm -f "$state_file"
    set_badge off
  fi

  [[ -n $ticket_line ]] && printf '\n%s\n' "$ticket_line"
  printf '\n%s%s · every %ss · r refresh · t ticket · q quit%s\n' \
    "$dim" "$(date '+%H:%M:%S')" "$interval" "$reset"
}

branch=""
while :; do
  render
  key=""
  # Status > 128: the timeout. Any other failure (no terminal, EOF) would
  # return at once and spin the loop: wait instead.
  read -rsn1 -t "$interval" key
  rc=$?
  ((rc != 0 && rc <= 128)) && sleep "$interval"
  case $key in
    q) set_badge off; exit 0 ;;
    t)
      id=$(printf '%s %s' "$branch" "$(gh pr view "$pr" "${repo_args[@]}" --json title -q .title 2>/dev/null)" \
        | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -n 1)
      if [[ -z $id ]]; then
        ticket_line="Ticket: no ticket ID in the PR title or branch."
      else
        printf '\n%sReading %s from Linear (about 10 s) …%s\n' "$dim" "$id" "$reset"
        line=$(ticket_status "$id")
        if [[ -z $line || $line == ERROR ]]; then
          ticket_line="Ticket $id: Claude could not read it ($(date '+%H:%M'))."
        else
          ticket_line="Ticket $id: $line ($(date '+%H:%M'))"
        fi
      fi
      ;;
  esac
done
