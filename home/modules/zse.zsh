# zse — Zellij session CLI for Claude Code workflows.
#
# Sourced from ~/.zshrc by home/modules/zellij.nix. Docs: docs/usage/zellij.md.
#
#   zse [-l USE_CASE] [-a AWS_PROFILE] [-t HINT] [NAME]   start or attach
#   zse ls                                      registry + live state + activity
#   zse pick                                    fzf picker (Ctrl Space in Zellij)
#   zse color [--all | NAME]                    Claude /color for running sessions
#   zse stop [NAME] | --all [--force]           stop, keep registered
#   zse kill [NAME]                             end: worktree prompt, cleanup, unregister
#   zse restore [NAME…]                         start stopped sessions in the background
#   zse switch NAME                             switch to a session (start it if stopped)
#   zse migrate NAME... | --all [--force]       old-style session → name schema
#
# Zellij session serialization is off (config.kdl). The registry below is the
# record of which sessions exist; each session is always (re)created from the
# current layout file, and `zse-claude --own` resumes its own conversation.

typeset -g ZSE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zse/sessions"
typeset -g ZSE_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zse/sessions"
# Repo short names for session names; filled by home/modules/zellij.nix
# before this file is sourced.
(( ${+ZSE_REPO_SHORT} )) || typeset -gA ZSE_REPO_SHORT
# Colours (#42 phase 3), also from zellij.nix: RGB per "<type>-<shade>",
# Claude /color per use case, and the generated per-shade Zellij configs.
(( ${+ZSE_SHADE_RGB} )) || typeset -gA ZSE_SHADE_RGB
(( ${+ZSE_CLAUDE_COLOR} )) || typeset -gA ZSE_CLAUDE_COLOR
typeset -g ZSE_ZELLIJ_CONFIG_DIR="${ZSE_ZELLIJ_CONFIG_DIR:-$HOME/.config/zellij/zse}"

# ----- Zellij state -----

# Print `live`, `exited` (a serialized session left over from before
# serialization was turned off) or `none`.
_z_session_state() {
  local line
  line=$(zellij list-sessions --no-formatting 2>/dev/null | awk -v n="$1" '$1 == n { print; exit }')
  if [[ -z $line ]]; then
    print none
  elif [[ $line == *EXITED* ]]; then
    print exited
  else
    print live
  fi
}

_z_session_exists() { [[ $(_z_session_state "$1") != none ]]; }

# ----- Registry: one KEY=VALUE file per session -----

_z_reg_file() { print -r -- "$ZSE_STATE_DIR/$1"; }

# _z_reg_get NAME KEY — print the value; fails when the session is unregistered.
_z_reg_get() {
  local f
  f=$(_z_reg_file "$1")
  [[ -r $f ]] || return 1
  sed -n "s/^$2=//p" "$f"
}

# _z_reg_write NAME USE_CASE DIR AWS_PROFILE [URL] — sets these keys and
# `last_started`; keeps `created`, `url` (when URL is not given) and every
# other key (the name keys below). `url` is the PR of a `review` session or
# the doc of a `review-doc` session; the claude panes read it (`zse-meta`).
_z_reg_write() {
  local f now created url
  f=$(_z_reg_file "$1")
  now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  created=$(_z_reg_get "$1" created 2>/dev/null)
  url=${5:-$(_z_reg_get "$1" url 2>/dev/null)}
  local -a keep
  [[ -r $f ]] && keep=(${(f)"$(grep -v -E '^(use_case|dir|aws_profile|created|last_started|url)=' "$f")"})
  mkdir -p "$ZSE_STATE_DIR"
  {
    printf 'use_case=%s\ndir=%s\naws_profile=%s\ncreated=%s\nlast_started=%s\n' \
      "$2" "$3" "$4" "${created:-$now}" "$now"
    [[ -n $url ]] && printf 'url=%s\n' "$url"
    ((${#keep})) && print -rl -- $keep
  } >"$f"
  return 0
}

# _z_reg_set NAME KEY VALUE — set one key of a registered session.
# Name keys (schema `names=2`, written at the start of a new session):
#   ticket, pr, owner, repo, slug   what the session is about
#   wt                              worktree dir name under .claude/worktrees
#   title, hint                     source title and the hint in the name
#   conv                            Claude conversation ID (set by `zse migrate`;
#                                   otherwise zse-claude derives it from the name)
_z_reg_set() {
  local f rest
  f=$(_z_reg_file "$1")
  [[ -r $f ]] || return 1
  rest=$(grep -v "^$2=" "$f")
  { [[ -n $rest ]] && print -r -- "$rest"; print -r -- "$2=${3//$'\n'/ }"; } >"$f"
}

# _z_find KEY VALUE [USE_CASE] — the first registered session whose KEY is
# VALUE (and whose use case is USE_CASE, when given).
_z_find() {
  local n
  for n in $(_z_reg_names); do
    [[ $(_z_reg_get "$n" "$1") == "$2" ]] || continue
    [[ -z ${3:-} || $(_z_reg_get "$n" use_case) == "$3" ]] || continue
    print -r -- "$n"
    return 0
  done
  return 1
}

# _z_resolve NAME — the session NAME refers to: NAME itself when it runs or is
# registered, else the registered session whose ticket ID is NAME, else
# `proj-NAME` / `exp-NAME`. Fails when there is none.
_z_resolve() {
  local n=$1 m
  if [[ $(_z_session_state "$n") != none ]] || _z_reg_get "$n" use_case >/dev/null 2>&1; then
    print -r -- "$n"
    return 0
  fi
  if m=$(_z_find ticket "${n:u}"); then
    print -r -- "$m"
    return 0
  fi
  for m in "proj-$n" "exp-$n"; do
    if _z_reg_get "$m" use_case >/dev/null 2>&1; then
      print -r -- "$m"
      return 0
    fi
  done
  return 1
}

_z_reg_names() {
  local f
  for f in "$ZSE_STATE_DIR"/*(N); do
    print -r -- "${f:t}"
  done
}

# ----- AWS side-car -----

# Path of the per-session AWS side-car (only written for `zse -a`). Stores
# AWS_PROFILE + AWS_SESSION_EXPIRATION so later attaches can warn on expiry.
_z_aws_sidecar() { print -r -- "$ZSE_CACHE_DIR/$1.env"; }

# Warn on stderr if the stored expiry is within 15 min or past. Removes the
# side-car silently if the session no longer exists.
_z_aws_warn() {
  emulate -L zsh
  local name="$1" sidecar
  sidecar=$(_z_aws_sidecar "$name")
  [[ -r $sidecar ]] || return 0
  if ! _z_session_exists "$name"; then
    rm -f "$sidecar"
    return 0
  fi
  local profile exp exp_epoch now_epoch remaining
  profile=$(sed -n 's/^AWS_PROFILE=//p' "$sidecar")
  exp=$(sed -n 's/^AWS_SESSION_EXPIRATION=//p' "$sidecar")
  [[ -n $exp ]] || return 0
  exp_epoch=$(date -jf '%Y-%m-%dT%H:%M:%SZ' "${exp%+00:00}Z" '+%s' 2>/dev/null) \
    || exp_epoch=$(date -jf '%Y-%m-%dT%H:%M:%SZ' "$exp" '+%s' 2>/dev/null) \
    || return 0
  now_epoch=$(date '+%s')
  remaining=$((exp_epoch - now_epoch))
  if ((remaining <= 0)); then
    print -u2 -r "zse: ⚠ session '$name' AWS creds (profile '$profile') expired at $exp — re-authenticate."
  elif ((remaining <= 900)); then
    print -u2 -r "zse: ⚠ session '$name' AWS creds (profile '$profile') expire in $((remaining / 60))m — re-authenticate soon."
  fi
}

# ----- Worktrees -----

# Worktree dir name for a session: the registry's `wt`. Sessions from before
# the name schema: review sessions are `review-<repo>-pr<n>` (or
# `review-doc-<repo>-pr<n>`), checked out into `.claude/worktrees/pr-<n>`;
# every other session uses its name.
_z_worktree_name() {
  local wt
  wt=$(_z_reg_get "$1" wt 2>/dev/null)
  if [[ -n $wt ]]; then
    print -r -- "$wt"
  elif [[ $1 =~ '^review-.+-pr([0-9]+)$' ]]; then
    print -r -- "pr-$match[1]"
  else
    print -r -- "$1"
  fi
}

# Print `origin/<default branch>` of the repo at $1. Order: the local
# `refs/remotes/origin/HEAD`, then `git remote set-head origin --auto` (asks
# the remote), then `gh repo view`. Fails when none of them knows it.
_z_default_branch() {
  emulate -L zsh
  local root="$1" ref
  ref=$(git -C "$root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) \
    || { git -C "$root" remote set-head origin --auto >/dev/null 2>&1 \
         && ref=$(git -C "$root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null); } \
    || { ref=$(cd -q "$root" && gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null) \
         && [[ -n $ref ]] && ref="origin/$ref"; }
  [[ -n $ref ]] || return 1
  print -r -- "$ref"
}

# _z_branch_worktree ROOT WT_NAME BRANCH — create (or re-attach)
# `.claude/worktrees/WT_NAME` on BRANCH, based on the fetched origin default
# branch, never on the main checkout's HEAD. Self-check: a new branch is
# exactly origin/<default>; an existing branch is reused with a warning about
# commits beyond it that do not name WT_NAME. Same rules as the
# tktl-eng-delivery plugin's `worktree.sh`, which ticket sessions use first.
_z_branch_worktree() {
  emulate -L zsh
  local root="$1" wt="$2" branch="$3" base dir
  dir="$root/.claude/worktrees/$wt"
  [[ -e $dir/.git ]] && return 0
  print -r "zse: fetching origin in $root …"
  if ! git -C "$root" fetch --quiet origin; then
    print -u2 -r "zse: ✗ git fetch origin failed in $root — not creating $dir from a stale base."
    return 1
  fi
  if ! base=$(_z_default_branch "$root"); then
    print -u2 -r "zse: ✗ cannot resolve origin's default branch in $root (origin/HEAD unset, gh failed)."
    return 1
  fi
  mkdir -p "${dir:h}"
  if git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$root" worktree add "$dir" "$branch" >/dev/null || return 1
    local -a foreign
    foreign=(${(f)"$(git -C "$dir" log --format='%h %s' "$base..HEAD" 2>/dev/null | grep -v -i -F -- "$wt")"})
    if ((${#foreign})); then
      print -u2 -r "zse: ⚠ existing branch $branch has ${#foreign} commit(s) beyond $base that do not name '$wt':"
      print -u2 -rl -- "      "${^foreign}
      print -u2 -r "      Check them before you push (git -C $dir log $base..HEAD)."
    fi
    return 0
  fi
  # --no-track: the branch must not get origin/<default> as its upstream.
  git -C "$root" worktree add --no-track -b "$branch" "$dir" "$base" >/dev/null || return 1
  local extra
  extra=$(git -C "$dir" rev-list "$base..HEAD" 2>/dev/null)
  if ! git -C "$dir" merge-base --is-ancestor "$base" HEAD || [[ -n $extra ]]; then
    git -C "$root" worktree remove --force "$dir" >/dev/null 2>&1
    git -C "$root" branch -D "$branch" >/dev/null 2>&1
    print -u2 -r "zse: ✗ self-check failed: new branch $branch was not exactly $base (commits beyond it: ${extra:-none}); removed it again."
    return 1
  fi
  print -r "zse: ✓ $branch created from $base ($(git -C "$dir" rev-parse --short HEAD))"
}

# _z_ticket_worktree ROOT ID — the ticket's worktree `.claude/worktrees/ID`:
# the tktl-eng-delivery plugin's `scripts/worktree.sh` when the plugin is
# installed (one implementation with the project master's ticket sessions),
# else `_z_branch_worktree` on `$ZSE_BRANCH_USER/ID`.
_z_ticket_worktree() {
  emulate -L zsh
  local root="$1" id="$2" plugin
  [[ -e $root/.claude/worktrees/$id/.git ]] && return 0
  plugin=$(jq -r '.plugins["tktl-eng-delivery@taktile-skills"][]? | select(.scope == "user") | .installPath' \
    "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json" 2>/dev/null)
  if [[ -n $plugin && -r $plugin/scripts/worktree.sh ]]; then
    bash "$plugin/scripts/worktree.sh" "$id" "$root" >/dev/null || return 1
  elif [[ -n ${ZSE_BRANCH_USER:-} ]]; then
    _z_branch_worktree "$root" "$id" "$ZSE_BRANCH_USER/$id"
  fi
}

# ----- Names: <type>-<repo>-<id>-<hint> -----

# _z_repo_short REPO — short repo name for session names: the entry in
# $ZSE_REPO_SHORT (a map from home/modules/zellij.nix), else: drop a
# `taktile-` prefix; 3+ parts (split on - and _) become their initials;
# otherwise the first 8 chars.
_z_repo_short() {
  emulate -L zsh
  local r=${1:l}
  if [[ -n ${ZSE_REPO_SHORT[$r]:-} ]]; then
    print -r -- "${ZSE_REPO_SHORT[$r]}"
    return
  fi
  r=${r#taktile-}
  local -a parts
  parts=(${(s:-:)${r//_/-}})
  if ((${#parts} >= 3)); then
    print -r -- "${(j::)${(@M)parts#?}}"
  else
    print -r -- "${${r//_/-}[1,8]%-}"
  fi
}

# _z_hint_clean TEXT — a valid hint: lower case, runs of other chars as `-`,
# at most 3 words of at most 8 chars.
_z_hint_clean() {
  emulate -L zsh
  setopt extended_glob
  local -a words out
  words=(${(s:-:)${${1:l}//[^a-z0-9]##/-}})
  local w
  for w in ${words[1,3]}; do
    out+=("${w[1,8]}")
  done
  print -r -- "${(j:-:)out}"
}

# _z_hint_rule TITLE — hint without AI: prefixes like `[ABC]`, `feat(x):` or
# `PEP:` and stop words dropped, then the first 3 words.
_z_hint_rule() {
  emulate -L zsh
  setopt extended_glob
  local t=${1:l}
  t=${t##\[[^\]]#\][[:space:]]#}
  t=${t##[a-z]##(\([^\)]#\))#\!#:[[:space:]]#}
  local -a stop words out
  stop=(a an the and or of for to in on at by with from into via is are be as it its this that add adds make makes use new)
  words=(${(s: :)${t//[^a-z0-9]##/ }})
  local w
  for w in $words; do
    ((${stop[(Ie)$w]})) && continue
    out+=("$w")
    ((${#out} == 3)) && break
  done
  _z_hint_clean "${(j:-:)out}"
}

typeset -g _ZSE_HINT_RULES='a reminder hint of at most 3 lower-case words (letters a-z and digits only, each word at most 8 characters) joined by "-", saying what it is about'

# _z_claude_p TOOLS PROMPT — one `claude -p` call with Haiku, 30 s timeout,
# run in $HOME without the session's markers (no repo context, no delivery
# rules). Prints the answer; fails on error or timeout.
_z_claude_p() {
  local -a tools
  [[ -n $1 ]] && tools=(--allowedTools "$1")
  local prompt=$2
  (
    cd -q "$HOME" || exit 1
    unset DELIVERY_SESSION ZSE_USE_CASE CLAUDECODE CLAUDE_CODE_ENTRYPOINT \
      CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION
    ${ZSE_TIMEOUT:-timeout} 30 claude -p --model haiku $tools \
      --output-format text "$prompt" </dev/null 2>/dev/null
  )
}

# _z_ticket_info ID — sets REPLY to the Linear title of ticket ID and
# REPLY_HINT to a suggested hint (one `claude -p` call through the Linear
# connector). Both empty when Claude cannot read the ticket.
_z_ticket_info() {
  emulate -L zsh
  local out
  REPLY="" REPLY_HINT=""
  print -u2 -r "zse: reading $1 from Linear for the hint (about 10 s) …"
  out=$(_z_claude_p mcp__claude_ai_Linear__get_issue \
    "Read Linear issue $1 with the get_issue tool. Reply with exactly two lines and nothing else. Line 1: the issue title. Line 2: $_ZSE_HINT_RULES. If you cannot read the issue, reply with the single line ERROR.") || return 0
  local -a lines
  lines=(${(f)out})
  [[ ${lines[1]:-ERROR} == ERROR ]] && return 0
  REPLY=${lines[1]}
  REPLY_HINT=${lines[2]:-}
  [[ $REPLY_HINT =~ '^[a-z0-9]{1,8}(-[a-z0-9]{1,8}){0,2}$' ]] || REPLY_HINT=$(_z_hint_rule "$REPLY")
}

# _z_hint_ai TITLE — a hint for TITLE from Claude; the rule-based hint when
# Claude fails or answers out of shape.
_z_hint_ai() {
  emulate -L zsh
  local out
  out=$(_z_claude_p "" "Title: $1
Reply with only $_ZSE_HINT_RULES.")
  out=${${out%%$'\n'*}// /}
  if [[ $out =~ '^[a-z0-9]{1,8}(-[a-z0-9]{1,8}){0,2}$' ]]; then
    print -r -- "$out"
  else
    _z_hint_rule "$1"
  fi
}

# _z_hint_ask WHAT TITLE SUGGESTION — sets REPLY to the hint. In a terminal,
# shows WHAT and TITLE and lets the user edit SUGGESTION (Enter accepts, an
# empty line means no hint); without a terminal, the suggestion.
_z_hint_ask() {
  emulate -L zsh
  local hint=$3
  if [[ -t 0 && -t 2 ]]; then
    print -u2 -r "zse: hint for $1${2:+ \"$2\"}"
    vared -p 'zse: hint (Enter accepts, empty = none): ' hint
  fi
  REPLY=$(_z_hint_clean "$hint")
}

# _z_name PREFIX ID [HINT] — `PREFIX-ID-HINT`, at most 40 chars (Zellij's
# socket path limit is about 55): hint words are dropped from the end first.
_z_name() {
  emulate -L zsh
  local base="$1-$2" hint=${3:-}
  while [[ -n $hint ]] && ((${#base} + 1 + ${#hint} > 40)); do
    [[ $hint == *-* ]] && hint=${hint%-*} || hint=""
  done
  print -r -- "$base${hint:+-$hint}"
}

# Remove a `.claude/worktrees/<name>` worktree if it is safe: no uncommitted
# changes, no unpushed commits. Prints why it skipped. Also deletes the
# `worktree-<name>` branch that `claude --worktree` leaves behind.
_z_cleanup_worktree() {
  emulate -L zsh
  local worktree="$1" wt_name="${1:t}"
  [[ -d $worktree ]] || return 0

  local dirty
  dirty=$(cd -q "$worktree" 2>/dev/null && git status --porcelain 2>/dev/null)
  if [[ -n $dirty ]]; then
    print -u2 -r "zse: worktree $worktree has uncommitted changes — skipping removal."
    return 1
  fi
  local upstream unpushed
  upstream=$(cd -q "$worktree" && git rev-parse --abbrev-ref '@{u}' 2>/dev/null)
  if [[ -n $upstream ]]; then
    unpushed=$(cd -q "$worktree" && git rev-list "${upstream}..HEAD" 2>/dev/null)
    if [[ -n $unpushed ]]; then
      print -u2 -r "zse: worktree $worktree has unpushed commits on $upstream — skipping removal."
      return 1
    fi
  fi

  local common_dir repo_root
  common_dir=$(cd -q "$worktree" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  repo_root="${common_dir%/.git}"
  if [[ ! -d $repo_root ]]; then
    print -u2 -r "zse: cannot resolve parent repo for $worktree."
    return 1
  fi

  (
    cd -q "$repo_root" || exit 1
    # `claude --worktree` locks the worktree; unlock fails silently when it
    # is already unlocked.
    git worktree unlock "$worktree" 2>/dev/null
    git worktree remove "$worktree" || exit 1
    git worktree prune 2>/dev/null
    # Only Claude's default branch; a `$ZSE_BRANCH_USER/<name>` or
    # `explore/<name>` branch stays (it holds the work, usually a PR).
    git branch -D "worktree-$wt_name" >/dev/null 2>&1 || true
  ) || return 1
  print -r "zse: removed worktree $worktree"
}

# ----- Launch -----

# ----- Terminal tint (Ghostty) -----
#
# The terminal background of a Zellij client follows the session:
# ZSE_TERM_TINT_PCT % (default 5, 0 = off) of the session's shade mixed into
# ZSE_TERM_BG (Ghostty 0x96f: #262427), set with OSC 11 on the client's tty.
# Zellij does not pass OSC 11 from a pane on to the terminal, so zse writes
# to the client's tty itself. ~/.cache/zse/clients/<tty> holds the session
# that zse last put on that client; a switch inside Zellij tints the
# clients of the current session (or the only client). OSC 111 resets the
# background when the client ends. A switch with Zellij's own session
# manager does not change the tint.
typeset -g ZSE_TERM_BG=${ZSE_TERM_BG:-38;36;39}
typeset -gi ZSE_TERM_TINT_PCT=${ZSE_TERM_TINT_PCT:-5}
typeset -g ZSE_CLIENT_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zse/clients"

# _z_mix NAME USE_CASE PCT — "r;g;b": PCT % of the session's shade colour
# (shade 1 when none is stored yet) mixed into ZSE_TERM_BG; empty without a
# use case or an RGB value for the shade.
_z_mix() {
  emulate -L zsh
  [[ -n $2 ]] || return 0
  local sh rgb i
  sh=$(_z_reg_get "$1" shade 2>/dev/null)
  rgb=${ZSE_SHADE_RGB[$(_z_color_type "$2")-${sh:-1}]:-}
  [[ -n $rgb ]] || return 0
  local -a c=(${(s:;:)rgb}) b=(${(s:;:)ZSE_TERM_BG}) out
  for i in 1 2 3; do out+=$((b[i] + (c[i] - b[i]) * $3 / 100)); done
  print -r -- "${(j:;:)out}"
}

# _z_term_hex NAME [USE_CASE] — "rr/gg/bb" for OSC 11; empty when the tint
# is off or the session has no shade colour.
_z_term_hex() {
  emulate -L zsh
  ((ZSE_TERM_TINT_PCT > 0)) || return 0
  local mix
  mix=$(_z_mix "$1" "${2:-$(_z_reg_get "$1" use_case 2>/dev/null)}" "$ZSE_TERM_TINT_PCT")
  [[ -n $mix ]] || return 0
  printf '%02x/%02x/%02x\n' ${(s:;:)mix}
}

# _z_tty_tint TTY NAME — set (or, without a colour, reset) the background of
# the terminal on TTY for session NAME, and remember NAME for that client.
_z_tty_tint() {
  emulate -L zsh
  local tty=$1 hex
  [[ -w $tty ]] || return 0
  hex=$(_z_term_hex "$2")
  if [[ -n $hex ]]; then
    printf '\e]11;rgb:%s\e\\' "$hex" >"$tty" 2>/dev/null
  else
    printf '\e]111\e\\' >"$tty" 2>/dev/null
  fi
  mkdir -p "$ZSE_CLIENT_DIR" && print -r -- "$2" >"$ZSE_CLIENT_DIR/${tty:t}"
}

# _z_tty_reset TTY — the theme's background again; forget the client.
_z_tty_reset() {
  [[ -w $1 ]] && printf '\e]111\e\\' >"$1" 2>/dev/null
  rm -f "$ZSE_CLIENT_DIR/${1:t}"
}

# _z_client_ttys SESSION — the ttys of the Zellij clients that show
# SESSION: the clients zse put on it, else the only Zellij client.
_z_client_ttys() {
  emulate -L zsh
  local -a all mine
  local t
  all=(${(f)"$(ps -axo tty=,comm= 2>/dev/null | awk '$1 != "??" && $2 ~ /(^|\/)zellij$/ { print "/dev/" $1 }' | sort -u)"})
  for t in $all; do
    [[ -r $ZSE_CLIENT_DIR/${t:t} && $(<"$ZSE_CLIENT_DIR/${t:t}") == "$1" ]] && mine+=$t
  done
  if ((${#mine})); then
    print -rl -- $mine
  elif ((${#all} == 1)); then
    print -r -- $all
  fi
}

# _z_attach NAME — switch to NAME inside Zellij, else attach in this
# terminal; the terminal background follows the session.
_z_attach() {
  local t
  if [[ -n ${ZELLIJ:-} ]]; then
    local -a ttys=($(_z_client_ttys "${ZELLIJ_SESSION_NAME:-}"))
    zellij action switch-session "$1"
    for t in $ttys; do _z_tty_tint "$t" "$1"; done
  else
    t=$(tty 2>/dev/null) || t=""
    [[ -n $t ]] && _z_tty_tint "$t" "$1"
    zellij attach "$1"
    [[ -n $t ]] && _z_tty_reset "$t"
  fi
}

# _z_launch NAME USE_CASE DIR AWS_PROFILE [bg] — register the session and
# create it from the current layout file. `bg` creates it in the background
# (no AWS: `assume` needs the YubiKey).
_z_launch() {
  emulate -L zsh
  local name=$1 use_case=$2 dir=$3 aws=$4 bg=${5:-}
  # Inside Zellij, a foreground start would nest a client: start it in the
  # background, then switch to it.
  local switch=""
  if [[ -z $bg && -n ${ZELLIJ:-} ]]; then
    if [[ -n $aws ]]; then
      print -u2 -r "zse: start '$name' with -a outside Zellij (assume needs the YubiKey and a foreground shell)."
      return 1
    fi
    bg=1 switch=1
  fi
  # A serialized session from before serialization was turned off would be
  # resurrected with its old saved layout — remove it first.
  if [[ $(_z_session_state "$name") == exited ]]; then
    zellij delete-session "$name" >/dev/null 2>&1
  fi
  _z_reg_write "$name" "$use_case" "$dir" "$aws"
  # The session's theme (#42 phase 3): Zellij ignores `options --theme`, so
  # start it with the shade's generated config.
  local cfg
  local -a zcfg
  cfg="$ZSE_ZELLIJ_CONFIG_DIR/$(_z_color_type "$use_case")-$(_z_shade "$name" "$use_case").kdl"
  if [[ -r $cfg ]]; then zcfg=(--config "$cfg"); else cfg=""; fi
  # A foreground client in this terminal: tint it now, reset it when the
  # client ends.
  local fg_tty=""
  if [[ -z $bg ]]; then
    fg_tty=$(tty 2>/dev/null) || fg_tty=""
    [[ -n $fg_tty ]] && _z_tty_tint "$fg_tty" "$name"
  fi
  (
    # -q: no chpwd hooks. direnv's hook would export the devshell's
    # `name=nix-shell-env` over our local `name`. The panes load the devshell
    # themselves (`zse-env`, home/modules/zellij.nix).
    cd -q "$dir" || exit 1
    # Run from a Claude Code tool shell, the new Zellij server (and every pane
    # in it) would inherit that session's markers: claude then turns
    # transcript saving off (CLAUDE_CODE_CHILD_SESSION) and carries the
    # parent's session ID and messaging socket.
    unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH \
      CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION \
      CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CODE_BRIDGE_SESSION_ID \
      CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN
    if [[ -n $bg ]]; then
      zellij $zcfg attach --create-background "$name" options --default-layout "$use_case"
    elif [[ -n $aws ]]; then
      local sidecar
      sidecar=$(_z_aws_sidecar "$name")
      mkdir -p "${sidecar:h}"
      # Hand off to the host's `assume` fn; the inner shell writes the
      # side-car with the credentials it just got, then execs zellij so every
      # pane inherits them.
      assume "$aws" -- zsh -c '
        printf "AWS_PROFILE=%s\nAWS_SESSION_EXPIRATION=%s\n" \
          "$AWS_PROFILE" "$AWS_SESSION_EXPIRATION" > "$1"
        cfg=(); [[ -n $4 ]] && cfg=(--config "$4")
        exec zellij "${cfg[@]}" -s "$2" -n "$3"
      ' zse-aws "$sidecar" "$name" "$use_case" "$cfg"
    else
      zellij $zcfg -s "$name" -n "$use_case"
    fi
  ) || { [[ -n $fg_tty ]] && _z_tty_reset "$fg_tty"; return 1; }
  [[ -n $fg_tty ]] && _z_tty_reset "$fg_tty"
  [[ -n $switch ]] && _z_attach "$name"
  return 0
}

# _z_doc_page_id URL — the 32-hex Notion page ID at the end of the URL's last
# path segment, or nothing.
_z_doc_page_id() {
  emulate -L zsh
  setopt extended_glob
  local seg=${${1%%[?#]*}%/}
  print -r -- "${(M)${seg:t}%%[0-9a-f](#c32)}"
}

# _z_doc_slug URL — session slug for a Notion page URL: the title part of the
# last path segment (lower case, non-alphanumeric runs as `-`, at most 34
# chars), then `-` and the first 8 chars of the page ID, so two pages with the
# same title get different sessions. Only the ID part when there is no title.
_z_doc_slug() {
  emulate -L zsh
  setopt extended_glob
  local seg=${${1%%[?#]*}%/}
  seg=${seg:t}
  local id
  id=$(_z_doc_page_id "$1")
  seg=${seg%$id}
  seg=${${seg:l}//[^a-z0-9]##/-}
  seg=${${seg#-}%-}
  # Reserve socket-path space for review-doc- and -<id8> on macOS.
  seg=${seg[1,34]%-}
  if [[ -n $seg && -n $id ]]; then
    print -r -- "$seg-${id[1,8]}"
  else
    print -r -- "${seg:-${id[1,8]}}"
  fi
}

# ----- Activity: what each session's Claude is doing -----

# _z_activity_load — fill the global maps from one `claude agents --json`
# call (about 0.2 s): ZSE_ACT[session] = busy | waiting | idle | ? (the
# interactive claude whose name is the session name; zse-claude sets
# --name), ZSE_AGENTS[session] = number of background Claude sessions
# running under a project session's start directory (its ticket
# sub-sessions). No hooks: Claude reports its own state, so a crashed
# session cannot stay "busy".
_z_activity_load() {
  emulate -L zsh
  typeset -gA ZSE_ACT ZSE_AGENTS
  ZSE_ACT=() ZSE_AGENTS=()
  local json line name kind st cwd n dir
  json=$(${ZSE_TIMEOUT:-timeout} 5 claude agents --json 2>/dev/null) || return 0
  local -A rank=(busy 3 waiting 2 idle 1 '?' 0)
  for line in ${(f)"$(print -r -- "$json" | ${ZSE_JQ:-jq} -r '.[] | [.name // "", .kind // "", (if .waitingFor then "waiting" else (.status // "?") end), .cwd // ""] | join("\u001f")' 2>/dev/null)"}; do
    # \x1f, not a tab: read collapses a leading empty field (no name).
    IFS=$'\x1f' read -r name kind st cwd <<<"$line"
    [[ $st == (busy|waiting|idle) ]] || st='?'
    if [[ $kind == background ]]; then
      for n in $(_z_reg_names); do
        [[ $(_z_reg_get "$n" use_case) == project ]] || continue
        dir=$(_z_reg_get "$n" dir)
        [[ -n $dir && $cwd == $dir* ]] && ((ZSE_AGENTS[$n]++))
      done
    elif [[ -n $name ]]; then
      ((${rank[$st]} > ${rank[${ZSE_ACT[$name]:-?}]})) || [[ -z ${ZSE_ACT[$name]:-} ]] && ZSE_ACT[$name]=$st
    fi
  done
}

# _z_is_active NAME — true when the session's Claude is busy or waiting for
# the user, or it has background agents running (after _z_activity_load).
_z_is_active() {
  [[ ${ZSE_ACT[$1]:-} == (busy|waiting) ]] || ((${ZSE_AGENTS[$1]:-0} > 0))
}

# _z_activity_word NAME — "busy, 2 agents" etc. for messages.
_z_activity_word() {
  local w=${ZSE_ACT[$1]:-?} a=${ZSE_AGENTS[$1]:-0}
  ((a)) && w+=", $a agent$( ((a > 1)) && print s)"
  print -r -- "$w"
}

# ----- Display: icons and colours per use case -----

typeset -gA ZSE_ICON=(ticket '◆' project '▲' review '✓' review-doc '¶' explore '✦' code '›' code-resume '›' daily '☀')
# ANSI 256 colours: ticket yellow, project orange, review green, review-doc
# teal, explore purple, code blue, daily grey.
typeset -gA ZSE_COLOR=(ticket 178 project 208 review 70 review-doc 37 explore 134 code 69 code-resume 69 daily 245)
typeset -gA ZSE_ACT_ICON=(busy '●' waiting '◐' idle '○' '?' '·')

# _z_color_type USE_CASE — the colour type: code-resume shares code.
_z_color_type() { print -r -- "${${1:-code}/#code-resume/code}"; }

# _z_shade NAME USE_CASE — the session's shade (1–4): the registry's
# `shade`, else the lowest one no other registered session of the colour
# type has (all four taken: cycle by count), stored in the registry.
_z_shade() {
  emulate -L zsh
  local name=$1 type n sh i
  sh=$(_z_reg_get "$name" shade 2>/dev/null)
  if [[ -z $sh ]]; then
    type=$(_z_color_type "$2")
    local -A used
    local -i count=0
    for n in $(_z_reg_names); do
      [[ $n == "$name" ]] && continue
      [[ $(_z_color_type "$(_z_reg_get "$n" use_case)") == "$type" ]] || continue
      ((count++))
      i=$(_z_reg_get "$n" shade 2>/dev/null) && [[ -n $i ]] && used[$i]=1
    done
    for i in 1 2 3 4; do
      [[ -z ${used[$i]:-} ]] && { sh=$i; break; }
    done
    [[ -z $sh ]] && sh=$((count % 4 + 1))
    _z_reg_set "$name" shade "$sh"
  fi
  print -r -- "$sh"
}

# _z_sgr NAME USE_CASE — SGR foreground for the session: its shade as
# 24-bit colour, else the type's 256 colour.
_z_sgr() {
  local sh rgb
  sh=$(_z_reg_get "$1" shade 2>/dev/null)
  rgb=${ZSE_SHADE_RGB[$(_z_color_type "$2")-$sh]:-}
  if [[ -n $sh && -n $rgb ]]; then
    print -r -- "38;2;$rgb"
  else
    print -r -- "38;5;${ZSE_COLOR[$2]:-250}"
  fi
}

# ----- Picker -----

# _z_age ISO_UTC — "5m", "3h", "2d" since the time.
_z_age() {
  emulate -L zsh
  zmodload -F zsh/datetime b:strftime p:EPOCHSECONDS
  local t s
  # strftime -r: no GNU / BSD `date` difference (Nix coreutils may come first).
  TZ=UTC strftime -r -s t '%Y-%m-%dT%H:%M:%SZ' "$1" 2>/dev/null || { print -r -- "-"; return; }
  s=$((EPOCHSECONDS - t))
  if ((s < 3600)); then print -r -- "$((s / 60))m"
  elif ((s < 86400)); then print -r -- "$((s / 3600))h"
  else print -r -- "$((s / 86400))d"; fi
}

# Picker groups (one per colour type, in this order) and their labels;
# sessions without a registered use case go to "other".
typeset -ga ZSE_GROUPS=(review review-doc ticket project explore code daily other)
typeset -gA ZSE_GROUP_LABEL=(review reviews review-doc 'doc reviews' ticket tickets
  project projects explore explorations code code daily daily other other)
# Row background in the picker: ZSE_TINT_PCT % of the session's shade mixed
# into ZSE_TERM_BG (see "Terminal tint").
typeset -gi ZSE_TINT_PCT=${ZSE_TINT_PCT:-14}

# _z_group USE_CASE — the picker group of a use case.
_z_group() {
  local g
  g=$(_z_color_type "$1")
  [[ -n $1 && -n ${ZSE_GROUP_LABEL[$g]:-} ]] && print -r -- "$g" || print -r -- other
}

# _z_tint NAME USE_CASE — SGR background for the session's picker row
# (shade 1 when none is stored yet); empty without a use case or RGB.
_z_tint() {
  emulate -L zsh
  local mix
  mix=$(_z_mix "$1" "$2" "$ZSE_TINT_PCT")
  [[ -n $mix ]] && print -r -- "48;2;$mix"
}

# _z_pick_width — the width of an fzf row: FZF_COLUMNS in a reload, else
# the terminal, minus the pointer gutter and the scrollbar.
_z_pick_width() {
  local w=${FZF_COLUMNS:-${COLUMNS:-$(tput cols 2>/dev/null)}}
  print -r -- $(( ${w:-100} - 3 ))
}

# Review states from the `zse-ci` pane (zse-ci.jq), with the markers that
# the pane also puts at the end of the tab name.
typeset -gA ZSE_REVIEW_MARK=(new '✱' submitted '↩' approved '✔' closed '✗' merged '⇥')

# _z_review NAME — read ~/.cache/zse/activity/NAME.pr: sets REPLY (state),
# REPLY_LABEL, REPLY_SUMMARY and REPLY_AT (ISO UTC of the last poll).
# Returns 1 when there is no state.
_z_review() {
  emulate -L zsh
  local f="${XDG_CACHE_HOME:-$HOME/.cache}/zse/activity/$1.pr" k v
  REPLY="" REPLY_LABEL="" REPLY_SUMMARY="" REPLY_AT="" REPLY_AUTHOR=""
  [[ -r $f ]] || return 1
  while IFS== read -r k v; do
    case $k in
      state) REPLY=$v ;;
      label) REPLY_LABEL=$v ;;
      summary) REPLY_SUMMARY=$v ;;
      at) REPLY_AT=$v ;;
      author) REPLY_AUTHOR=$v ;;
    esac
  done <"$f"
  # A file from before the states: only `new=` and `summary=`.
  [[ -z $REPLY && -n $REPLY_SUMMARY ]] && REPLY=new
  [[ -n $REPLY ]]
}

# _z_review_badge NAME FG RUNNING — the review state for a picker row:
# `✱ <summary>` inverse in the session colour (needs attention), `↩ <how>`
# dim, `✔ approved` green, `✗ closed` / `⇥ merged` grey. A stopped session
# adds the age of the state (`· 2d`): zse-ci only runs in running sessions.
_z_review_badge() {
  emulate -L zsh
  _z_review "$1" || return 0
  local e=$'\e' text="${ZSE_REVIEW_MARK[$REPLY]:-?} ${${REPLY_SUMMARY:-$REPLY_LABEL}:-$REPLY}"
  [[ $3 == running || -z $REPLY_AT ]] || text+=" · $(_z_age "$REPLY_AT")"
  case $REPLY in
    new) print -rn -- "${e}[1;7;${2}m ${text} ${e}[27;22;39m" ;;
    submitted) print -rn -- "${e}[2m${text}${e}[22m" ;;
    approved) print -rn -- "${e}[32m${text}${e}[39m" ;;
    *) print -rn -- "${e}[90m${text}${e}[39m" ;;
  esac
}

# _z_pick_lines — one tab-separated line per session for fzf: the name
# (hidden, for the action), then the display: activity, type icon in the
# type colour, name, state, age, new-on-PR badge, agents, title, on a
# background tinted with the session's shade. Sessions are grouped by type
# (ZSE_GROUPS); a separator line with an empty name heads each group.
# Inside a group: running first (busy, waiting, idle), then stopped;
# newest first.
_z_pick_lines() {
  emulate -L zsh
  setopt extended_glob
  _z_activity_load
  local -A live
  local l
  for l in ${(f)"$(zellij list-sessions --no-formatting --short 2>/dev/null)"}; do
    live[$l]=1
  done
  local n uc st act sort badge agents title fg bg icon age started g
  local head plain row
  local -i width=$(_z_pick_width) rest namew=0 badgew=0
  local -A badges sorts authors
  local -a rows
  local -A order=(busy 1 waiting 2 idle 3 '?' 4)
  local -a names=($(_z_reg_names) ${(k)live})
  local e=$'\e'
  names=(${(u)names})
  # Pass 1: the review badges and sort keys; the name and badge columns get
  # the width of their widest value.
  for n in $names; do
    uc=$(_z_reg_get "$n" use_case 2>/dev/null) || uc=""
    if [[ -n ${live[$n]:-} ]]; then
      st=running act=${ZSE_ACT[$n]:-?}
      sort=${order[$act]}
    else
      st=stopped act=""
      sort=5
    fi
    badge=$(_z_review_badge "$n" "$(_z_sgr "$n" "$uc")" "$st")
    _z_review "$n" # REPLY for the sort (the badge runs in a subshell)
    # Reviews that need attention first in their group, closed / merged last.
    case $REPLY in
      new) sort=0 ;;
      closed | merged) sort=6 ;;
    esac
    badges[$n]=$badge sorts[$n]=$sort
    # The PR author after a review's name: `rev-… (theo)`
    [[ -n $REPLY_AUTHOR ]] && authors[$n]=" ($REPLY_AUTHOR)"
    plain=${badge//$e\[[0-9;]#m/}
    l="$n${authors[$n]:-}"
    ((${(m)#l} > namew)) && namew=${(m)#l}
    ((${(m)#plain} > badgew)) && badgew=${(m)#plain}
  done
  for n in $names; do
    uc=$(_z_reg_get "$n" use_case 2>/dev/null) || uc=""
    if [[ -n ${live[$n]:-} ]]; then
      st=running act=${ZSE_ACT[$n]:-?}
    else
      st=stopped act=""
    fi
    badge=${badges[$n]} sort=${sorts[$n]}
    agents=${ZSE_AGENTS[$n]:-0}
    title=$(_z_reg_get "$n" title 2>/dev/null)
    [[ -z $title ]] && title=$(_z_reg_get "$n" url 2>/dev/null)
    fg=$(_z_sgr "$n" "$uc") bg=$(_z_tint "$n" "$uc") icon=${ZSE_ICON[$uc]:-·}
    started=$(_z_reg_get "$n" last_started 2>/dev/null)
    age=$(_z_age "$started")
    g=$(_z_group "$uc")
    # Only foreground / weight resets inside the row: a full reset would
    # end the background before the padding.
    head="${${act:+${ZSE_ACT_ICON[$act]:-·}}:- } ${e}[${fg}m${icon}${e}[39m $n${authors[$n]:+${e}[2m${authors[$n]}${e}[22m}${(l:namew - ${(m)#n} - ${(m)#authors[$n]}:: :)} $(printf '%-7s %4s' "$st" "$age")"
    if ((badgew)); then
      plain=${badge//$e\[[0-9;]#m/}
      head+="  ${badge}${(l:badgew - ${(m)#plain}:: :)}"
    fi
    ((agents)) && head+="  [$agents agents]"
    plain=${head//$e\[[0-9;]#m/}
    rest=$((width - ${(m)#plain} - 2))
    ((rest > 0)) && head+="  ${e}[2m${title[1,rest]}${e}[22m"
    plain=${head//$e\[[0-9;]#m/}
    rest=$((width - ${(m)#plain}))
    ((rest > 0)) && head+=${(l:rest:: :)}
    row=$head
    [[ -n $bg ]] && row="${e}[${bg}m${head}${e}[0m"
    rows+=("${ZSE_GROUPS[(ie)$g]} $sort ${started:-0}	$n	$row")
  done
  # Column header (fzf --header-lines=1: fixed, not selectable)
  head="    ${(r:namew:: :):-SESSION} $(printf '%-7s %4s' STATE AGE)"
  ((badgew)) && head+="  ${(r:badgew:: :):-REVIEW}"
  print -r -- "	${e}[2m${head}  TITLE${e}[22m"
  (($#rows)) || return 0
  # Rows are "group activity last_started<TAB>name<TAB>display": sort by
  # group, activity, then newest first; drop the sort key; a separator
  # before each group.
  local last="" gi label line
  for line in ${(f)"$(print -rl -- $rows | sort -k1,1n -k2,2n -k3,3r)"}; do
    gi=${line%% *}
    if [[ $gi != $last ]]; then
      g=${ZSE_GROUPS[gi]} label="${ZSE_GROUP_LABEL[$g]} "
      rest=$((width - ${(m)#label}))
      ((rest > 0)) && label+=${(l:rest::─:)}
      print -r -- "	${e}[38;5;${ZSE_COLOR[$g]:-245}m${label}${e}[0m"
      last=$gi
    fi
    print -r -- "${line#*	}"
  done
}

# _z_pick_preview NAME — details for the fzf preview.
_z_pick_preview() {
  emulate -L zsh
  local n=$1 f
  [[ -n $n ]] || return 0 # a group separator
  if [[ $n == https://* ]]; then # a review request
    local src
    for src in $ZSE_REQ_SOURCES; do
      ${ZSE_JQ:-jq} -r --arg u "$n" '.[] | select(.url == $u and .text != null)
        | "\(.source) · \(.from) · \(.at[0:16] | sub("T"; " ")): \(.text)"' \
        "$ZSE_REQ_DIR/$src.json" 2>/dev/null
    done
    print
    gh pr view "$n" 2>/dev/null | head -n 60
    return 0
  fi
  f=$(_z_reg_file "$n")
  print -r -- "$n"
  print
  if [[ -r $f ]]; then
    grep -E '^(use_case|dir|title|url|ticket|pr|wt|hint|aws_profile|created|last_started)=' "$f" | sed 's/=/: /'
    local root wt
    root=$(git -C "$(_z_reg_get "$n" dir)" rev-parse --show-toplevel 2>/dev/null)
    wt=$(_z_worktree_name "$n")
    [[ -n $root && -d $root/.claude/worktrees/$wt ]] && print -r -- "worktree: $root/.claude/worktrees/$wt"
  else
    print "not registered (started without zse)"
  fi
  if _z_review "$n"; then
    print
    print -r -- "review: ${ZSE_REVIEW_MARK[$REPLY]:-?} $REPLY${REPLY_LABEL:+ ($REPLY_LABEL)}${REPLY_SUMMARY:+ · $REPLY_SUMMARY since your last review}${REPLY_AT:+ · checked $(_z_age "$REPLY_AT") ago}"
  fi
}

# ----- Review requests (roadmap #47) -----
#
# A second view in `zse pick` (Tab): open review requests. Each source
# runs in the background when the view opens, writes
# ~/.cache/zse/requests/<source>.json and, when the picker still shows the
# requests, reloads it through the fzf socket (`--listen-unsafe` on a
# socket in that user-only directory). One lock directory per source stops
# a second run while one runs.
typeset -g ZSE_REQ_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zse/requests"
typeset -ga ZSE_REQ_SOURCES=(github team rereview slack)
typeset -gA ZSE_REQ_LABEL=(github 'requested from you' team 'platform-team' rereview 'new commits' slack 'Slack')
typeset -gA ZSE_REQ_TAG=(github gh team team slack slack)
# The requests view: one icon per source (Nerd Font: Slack, GitHub), in
# this order; the rows sort by their first source, then oldest first.
# Linear (no logo in the Nerd Font: a circled L) and "new commits since my
# review" (a clock with an arrow).
typeset -gA ZSE_REQ_ICON=(slack $'\uf198' linear $'\U000f0c0d' github $'\uf09b' rereview $'\U000f02da' team '#')
typeset -ga ZSE_REQ_RANK=(slack linear github rereview team)
# The order of the rows: Slack (DMs, mentions, SH in your shift) first,
# then the direct requests (Linear, GitHub), then new commits since your
# review, then the team.
typeset -gA ZSE_REQ_TIER=(slack 0 linear 1 github 1 rereview 2 team 3)
# Platform Support (incident.io): SH requests count only in your shifts.
typeset -g ZSE_REQ_SCHEDULE=${ZSE_REQ_SCHEDULE:-01KY4FJZ1S64RZPPN1JR95R9TQ}
typeset -gA ZSE_REQ_QUERY=(
  github 'user-review-requested:@me'
  team 'team-review-requested:taktile-org/platform-team draft:false -author:app/taktile-claudius -author:app/eng-automations'
)
typeset -gi ZSE_REQ_DAYS=7
typeset -gi ZSE_REQ_SLACK_TIMEOUT=${ZSE_REQ_SLACK_TIMEOUT:-180}
# The Slack search (claude -p, Haiku, the Slack connector's search and
# profile tools only). SINCE / BEFORE: the window, YYYY-MM-DD (UTC).
typeset -g ZSE_REQ_SLACK_PROMPT='Find GitHub pull request links in Slack messages that ask me to review, sent on or after SINCE (UTC). Search with the Slack search tool; run these searches, each with after:BEFORE:
1. Direct messages and group DMs to me with a PR link: `is:dm github.com/ pull` and `to:me github.com/ pull`.
2. Messages in any channel that mention me and have a PR link: `@me github.com/ pull` (if `@me` does not work, find my user ID with the profile tool and use `<@ID>`).
3. Messages in #team-platform with a PR link: `in:#team-platform github.com/ pull`. Use "via":"sh" for these, or "@" when the message mentions me by name.
4. Linear review requests in my DMs: `from:@Linear requested your review` and `from:@Linear re-requested your review`. These name the PR as `<owner>/<repo>#<number>`: use https://github.com/<owner>/<repo>/pull/<number> as the link, "via":"linear" and the person who requested the review as "from".
Ignore messages that I sent myself.
A message can have more than one PR link: list all of them. Copy each GitHub link exactly as it is in the message, also when it has a suffix such as /changes, /files or #diff-….
Reply with JSON lines only, one per message, no other text:
{"urls":["<every GitHub PR link in the message>"],"via":"dm" | "@" | "sh" | "linear" | "#<channel>","from":"<sender display name>","at":"<message time, ISO 8601 UTC>","text":"<first 120 characters of the message>"}
If you find none, reply with nothing. If the search tool fails, reply ERROR.'
# A command for fzf actions: run a zse function in a fresh zsh.
typeset -g ZSE_ZCALL='zsh -c '\''source "$ZSE_SOURCE"; "$@"'\'' zse'

# _z_req_fetch SOURCE — run one GitHub source; write its cache (or
# <source>.error), then tell the picker.
_z_req_fetch() {
  emulate -L zsh
  setopt extended_glob
  zmodload -F zsh/datetime b:strftime p:EPOCHSECONDS
  local src=$1 lock="$ZSE_REQ_DIR/$1.lock" q json
  mkdir -p "$ZSE_REQ_DIR"
  # A lock older than 5 minutes is left over from a run that died.
  [[ -n $lock(#qN/mm+5) ]] && rm -rf "$lock"
  mkdir "$lock" 2>/dev/null || return 0
  if [[ $src == slack || $src == rereview ]]; then
    if _z_req_$src "$lock"; then
      rm -f "$ZSE_REQ_DIR/$src.error"
    else
      print -r -- "$(strftime '%H:%M' $EPOCHSECONDS)" >"$ZSE_REQ_DIR/$src.error"
    fi
    rm -rf "$lock"
    _z_req_notify
    return 0
  fi
  q=${ZSE_REQ_QUERY[$src]:-}
  [[ $src == team ]] && q+=" updated:>=$(strftime '%Y-%m-%d' $((EPOCHSECONDS - ZSE_REQ_DAYS * 86400)))"
  if [[ -n $q ]] \
    && json=$(${ZSE_TIMEOUT:-timeout} 30 gh search prs --state=open --limit 100 \
      --json url,repository,number,title,author,createdAt -- ${=q} 2>/dev/null) \
    && json=$(print -r -- "$json" | ${ZSE_JQ:-jq} -c --arg s "$src" \
      '[.[] | {url, repo: .repository.nameWithOwner, number, title,
               author: (.author.login // "" | sub("^app/"; "") | sub("\\[bot\\]$"; "")), at: .createdAt, source: $s}]'); then
    print -r -- "$json" >"$lock/out" && mv "$lock/out" "$ZSE_REQ_DIR/$src.json"
    rm -f "$ZSE_REQ_DIR/$src.error"
  else
    print -r -- "$(strftime '%H:%M' $EPOCHSECONDS)" >"$ZSE_REQ_DIR/$src.error"
  fi
  rm -rf "$lock"
  _z_req_notify
}

# The shift lookup (claude -p, Haiku, incident.io identity and schedule
# tools only). Claude copies the raw shifts; zse picks yours with jq.
typeset -g ZSE_REQ_SHIFT_PROMPT='Call the incident.io identity_show tool, then schedule_show with id SCHEDULE, from FROM, until UNTIL. Reply with one line of compact JSON and nothing else: {"me":"<user.id from identity_show>","shifts":[<every item of shifts and next_shifts as {"user_id":…,"start_at":…,"end_at":…}>]}. Copy the values exactly; do not filter or merge. If a tool fails, reply ERROR.'

# _z_req_shifts — your Platform Support shifts from ZSE_REQ_DAYS days ago
# to tomorrow in shifts.json ([{start, end}]), looked up at most once a day.
# Fails (and keeps the old file) when incident.io cannot be read.
_z_req_shifts() {
  emulate -L zsh
  setopt extended_glob
  zmodload -F zsh/datetime b:strftime p:EPOCHSECONDS
  local f="$ZSE_REQ_DIR/shifts.json" out json p
  [[ -n $f(#qN.mh-24) ]] && return 0
  p=${ZSE_REQ_SHIFT_PROMPT//SCHEDULE/$ZSE_REQ_SCHEDULE}
  p=${p//FROM/$(TZ=UTC strftime '%Y-%m-%dT%H:%M:%SZ' $((EPOCHSECONDS - ZSE_REQ_DAYS * 86400)))}
  p=${p//UNTIL/$(TZ=UTC strftime '%Y-%m-%dT%H:%M:%SZ' $((EPOCHSECONDS + 86400)))}
  out=$(
    cd "$HOME" || exit 1
    unset DELIVERY_SESSION ZSE_USE_CASE CLAUDECODE CLAUDE_CODE_ENTRYPOINT \
      CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION
    ${ZSE_TIMEOUT:-timeout} 120 claude -p --model haiku \
      --allowedTools mcp__claude_ai_incident_io__identity_show,mcp__claude_ai_incident_io__schedule_show \
      --output-format text "$p" </dev/null 2>/dev/null
  ) || return 1
  json=$(print -r -- "$out" | ${ZSE_JQ:-jq} -Rc 'fromjson? | select(.me and .shifts)
    | .me as $me | [.shifts[] | select(.user_id == $me) | {start: .start_at[0:19], end: .end_at[0:19]}]' | head -n 1)
  [[ -n $json ]] || return 1
  print -r -- "$json" >"$f.tmp" && mv "$f.tmp" "$f"
}

# _z_req_slack LOCKDIR — the Slack source: search the messages since the
# last search (minus 1 h, at most ZSE_REQ_DAYS days), merge them with the
# earlier ones by PR URL, drop requests older than ZSE_REQ_DAYS days, your
# own PRs, PRs that are closed or merged, and SH requests (`sh`,
# #team-platform) sent outside your Platform Support shifts (all stay when
# the shifts are unknown); add the PR data from GitHub (one GraphQL call);
# write slack.json and the time of the search.
# _z_req_slack_parse — the Slack search reply (JSON lines) on stdin → a JSON
# array with one entry per PR link: {url, via, from, at, text}.
_z_req_slack_parse() {
  ${ZSE_JQ:-jq} -Rc '
    fromjson? | select(type == "object")
    | . as $m
    | ([.urls?, .url?] | flatten | map(select(type == "string")) | .[])
    | sub("[?#].*$"; "") | sub("^(?<u>https://github\\.com/[^/]+/[^/]+/pull/[0-9]+).*$"; "\(.u)")
    | select(test("^https://github\\.com/[^/]+/[^/]+/pull/[0-9]+$"))
    | {url: ., via: ($m.via // "slack"), from: ($m.from // ""), at: ($m.at // ""), text: ($m.text // "")}' \
    | ${ZSE_JQ:-jq} -sc 'unique_by([.url, .via, .at])'
}

_z_req_slack() {
  emulate -L zsh
  zmodload -F zsh/datetime b:strftime p:EPOCHSECONDS
  local lock=$1 now=$EPOCHSECONDS last since out new old merged q i
  local jq=${ZSE_JQ:-jq}
  last=0
  [[ -r $ZSE_REQ_DIR/last-slack-search ]] && last=$(<"$ZSE_REQ_DIR/last-slack-search")
  [[ $last == <-> ]] || last=0
  since=$((last - 3600))
  ((since < now - ZSE_REQ_DAYS * 86400)) && since=$((now - ZSE_REQ_DAYS * 86400))
  local p=${ZSE_REQ_SLACK_PROMPT//SINCE/$(TZ=UTC strftime '%Y-%m-%d' $since)}
  p=${p//BEFORE/$(TZ=UTC strftime '%Y-%m-%d' $((since - 86400)))}
  out=$(
    cd "$HOME" || exit 1
    unset DELIVERY_SESSION ZSE_USE_CASE CLAUDECODE CLAUDE_CODE_ENTRYPOINT \
      CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION
    ${ZSE_TIMEOUT:-timeout} $ZSE_REQ_SLACK_TIMEOUT claude -p --model haiku \
      --allowedTools mcp__claude_ai_Slack__slack_search_public_and_private,mcp__claude_ai_Slack__slack_read_user_profile \
      --output-format text "$p" </dev/null 2>/dev/null
  ) || return 1
  [[ $out == ERROR* ]] && return 1
  # Valid lines only; one entry per PR link of a message (`urls`, or
  # `url`), the URL without a suffix (/changes, /files, #…, ?…).
  new=$(print -r -- "$out" | _z_req_slack_parse) || return 1
  old=$($jq -c '[.[] | {url, via: .source, from, at, text}]' "$ZSE_REQ_DIR/slack.json" 2>/dev/null) || old='[]'
  # One entry per URL and source: the earliest request.
  merged=$($jq -nc --argjson a "$old" --argjson b "$new" \
    --arg cut "$(TZ=UTC strftime '%Y-%m-%dT%H:%M:%SZ' $((now - ZSE_REQ_DAYS * 86400)))" '
    $a + $b | map(select(.at >= $cut)) | group_by([.url, .via]) | map(min_by(.at))') || return 1
  # PR data and my latest review, for all PRs in one GraphQL call.
  local -a urls=(${(f)"$(print -r -- "$merged" | $jq -r '[.[].url] | unique[]')"})
  local pr_data='{}'
  if (($#urls)); then
    q='query { viewer { login }'
    for i in {1..$#urls}; do
      [[ $urls[i] =~ '^https://github.com/([^/]+)/([^/]+)/pull/([0-9]+)$' ]] || continue
      q+=" p$i: repository(owner: \"$match[1]\", name: \"$match[2]\") { pullRequest(number: $match[3]) { url title state author { login } reviews(last: 30) { nodes { author { login } submittedAt } } } }"
    done
    q+=' }'
    pr_data=$(${ZSE_TIMEOUT:-timeout} 30 gh api graphql -f query="$q" 2>/dev/null \
      | $jq -c '.data as $d | ($d.viewer.login) as $me
          | [$d | to_entries[] | select(.key != "viewer") | .value.pullRequest
             | select(. != null and .author.login != $me)
             | {key: .url, value: {title, state, author: (.author.login // "" | sub("\\[bot\\]$"; "")),
                 reviewed: ([.reviews.nodes[] | select(.author.login == $me) | .submittedAt] | max)}}]
          | from_entries') || return 1
  fi
  local shifts=null
  _z_req_shifts && shifts=$(<"$ZSE_REQ_DIR/shifts.json")
  print -r -- "$merged" | $jq -c --argjson prs "$pr_data" --argjson shifts "$shifts" '
    [.[] | . as $r | $prs[$r.url] as $p | select($p != null and $p.state == "OPEN")
     | select(.via != "sh" or $shifts == null
              or any($shifts[]; .start <= ($r.at[0:19]) and ($r.at[0:19]) < .end))
     | ($r.url | capture("^https://github\\.com/(?<o>[^/]+)/(?<n>[^/]+)/pull/(?<num>[0-9]+)$")) as $m
     | {url, repo: "\($m.o)/\($m.n)", number: ($m.num | tonumber), title: $p.title, author: $p.author,
        at, source: .via, group: (if .via == "linear" then "linear" else "slack" end),
        from, text, reviewed: $p.reviewed}]' >"$lock/out" || return 1
  mv "$lock/out" "$ZSE_REQ_DIR/slack.json"
  print -r -- "$now" >"$ZSE_REQ_DIR/last-slack-search"
}

# _z_req_rereview LOCKDIR — open PRs by others that you reviewed, with
# commits after your latest review (updated in the last ZSE_REQ_DAYS days;
# one GraphQL search). `at` is the newest commit.
_z_req_rereview() {
  emulate -L zsh
  zmodload -F zsh/datetime b:strftime p:EPOCHSECONDS
  local q json
  q="is:pr is:open reviewed-by:@me -author:@me archived:false updated:>=$(TZ=UTC strftime '%Y-%m-%d' $((EPOCHSECONDS - ZSE_REQ_DAYS * 86400)))"
  json=$(${ZSE_TIMEOUT:-timeout} 30 gh api graphql -f q="$q" -f query='
    query($q: String!) { viewer { login }
      search(type: ISSUE, query: $q, first: 50) { nodes { ... on PullRequest {
        url number title repository { nameWithOwner } author { login }
        commits(last: 1) { nodes { commit { committedDate } } }
        reviews(last: 50) { nodes { author { login } submittedAt } } } } } }' 2>/dev/null \
    | ${ZSE_JQ:-jq} -c '.data.viewer.login as $me | [.data.search.nodes[] | select(.url)
        | ([.reviews.nodes[] | select(.author.login == $me) | .submittedAt] | max) as $mine
        | (.commits.nodes[0].commit.committedDate // "") as $last
        | select($mine != null and $last > $mine)
        | {url, repo: .repository.nameWithOwner, number, title,
           author: (.author.login // "" | sub("^app/"; "") | sub("\\[bot\\]$"; "")),
           at: $last, source: "rereview"}]') || return 1
  [[ -n $json ]] || return 1
  print -r -- "$json" >"$1/out" && mv "$1/out" "$ZSE_REQ_DIR/rereview.json"
}

# _z_req_notify — reload the picker's requests view (no-op without one).
_z_req_notify() {
  [[ -n ${ZSE_FZF_SOCK:-} && -S $ZSE_FZF_SOCK ]] || return 0
  curl -s --max-time 2 --unix-socket "$ZSE_FZF_SOCK" -X POST http://localhost \
    -d "transform:$ZSE_ZCALL _z_req_on_update" >/dev/null 2>&1
}

# fzf actions. The prompt says which view is open.
_z_req_on_update() {
  [[ $FZF_PROMPT == requests* ]] && print -r -- "reload($ZSE_ZCALL _z_req_lines)"
}
_z_req_toggle() {
  if [[ $FZF_PROMPT == requests* ]]; then
    print -r -- "change-prompt(> )+reload($ZSE_ZCALL _z_pick_lines)+change-header:$(_z_pick_header)"
  else
    print -r -- "change-prompt(requests> )+reload($ZSE_ZCALL _z_req_lines --fetch)+change-header:$(_z_req_header)"
  fi
}
_z_req_refresh() {
  if [[ $FZF_PROMPT == requests* ]]; then
    print -r -- "reload($ZSE_ZCALL _z_req_lines --fetch)"
  else
    print -r -- "reload($ZSE_ZCALL _z_pick_lines)"
  fi
}
_z_pick_header() {
  print -r -- 'Enter switch · Tab review requests · Ctrl-R reload · Esc close   ● busy ◐ waiting ○ idle · review: ✱ new ↩ submitted ✔ approved ✗ closed ⇥ merged'
}
_z_req_header() {
  print -r -- 'Enter start the review (dim: switch to its session) · Tab sessions · Ctrl-R search again · Esc close'
}

# _z_req_lines [--fetch] — the requests view: a status line, then one row
# per PR ("key<TAB>display"; the key is the PR URL, or the name of its
# review session), grouped by source in ZSE_REQ_SOURCES order (a PR in
# more than one source goes to the first), oldest first. --fetch starts the
# sources in the background first.
_z_req_lines() {
  emulate -L zsh
  setopt extended_glob
  zmodload -F zsh/datetime b:strftime p:EPOCHSECONDS
  zmodload -F zsh/stat b:zstat
  local src n u e=$'\e'
  if [[ ${1:-} == --fetch ]]; then
    mkdir -p "$ZSE_REQ_DIR"
    for src in $ZSE_REQ_SOURCES; do
      ( _z_req_fetch "$src" ) </dev/null >/dev/null 2>&1 &!
      # Let the lock appear before the status line reads it.
    done
    sleep 0.1
  fi
  local -i width=$(_z_pick_width) rest
  # Review sessions by PR URL.
  local -A sess
  for n in $(_z_reg_names); do
    [[ $(_z_reg_get "$n" use_case 2>/dev/null) == review ]] || continue
    u=$(_z_reg_get "$n" url 2>/dev/null)
    [[ -n $u ]] && sess[$u]=$n
  done

  # Status: per source, loading / failed / the age of its cache.
  local -a st
  local -a mt
  for src in $ZSE_REQ_SOURCES; do
    if [[ -d $ZSE_REQ_DIR/$src.lock ]]; then
      st+="${ZSE_REQ_LABEL[$src]} … searching"
    elif [[ -r $ZSE_REQ_DIR/$src.error ]]; then
      st+="${ZSE_REQ_LABEL[$src]} ✗ failed $(<"$ZSE_REQ_DIR/$src.error")"
    elif [[ -r $ZSE_REQ_DIR/$src.json ]]; then
      zstat -A mt +mtime "$ZSE_REQ_DIR/$src.json"
      st+="${ZSE_REQ_LABEL[$src]} ✓ $(_z_age "$(TZ=UTC strftime '%Y-%m-%dT%H:%M:%SZ' $mt[1])")"
    else
      st+="${ZSE_REQ_LABEL[$src]} —"
    fi
  done
  local -a files=() rows=()
  for src in $ZSE_REQ_SOURCES; do
    [[ -r $ZSE_REQ_DIR/$src.json ]] && files+="$ZSE_REQ_DIR/$src.json"
  done
  local order tier
  order=$(print -rl -- $ZSE_REQ_RANK | ${ZSE_JQ:-jq} -Rsc 'split("\n") | map(select(. != ""))')
  tier=$(for src in ${(k)ZSE_REQ_TIER}; do print -r -- "$src ${ZSE_REQ_TIER[$src]}"; done \
    | ${ZSE_JQ:-jq} -Rsc 'split("\n") | map(select(. != "") | split(" ") | {key: .[0], value: (.[1] | tonumber)}) | from_entries')
  (($#files)) && rows=(${(f)"$(${ZSE_JQ:-jq} -rs --argjson order "$order" --argjson tier "$tier" '
      [.[][]] | group_by(.url)
      | map({url: .[0].url, repo: .[0].repo, number: .[0].number, title: .[0].title,
             author: .[0].author, at: (map(.at) | min),
             reviewed: (map(.reviewed // empty) | max),
             groups: (map(.group // .source) | unique | sort_by(. as $s | $order | index($s)))})
      | map(. + {g: ([.groups[] | $tier[.] // 9] | min)})
      | sort_by(.g, .at)[]
      | [.g, .url, .repo, .number, (.title | gsub("\t"; " ")), .author, .at, (.groups | join(",")),
         (if .reviewed != null and .reviewed > .at then .reviewed else "" end)] | @tsv
    ' $files 2>/dev/null)"})
  # The VIA column fits the row with the most sources.
  local -i iconw=6 n_src
  local -a via
  local line
  for line in $rows; do
    via=(${(s:,:)${${(ps:\t:)line}[8]}})
    n_src=$#via
    ((2 * n_src > iconw)) && iconw=$((2 * n_src))
  done
  # Column header (fzf --header-lines=1), then the status line.
  print -r -- "	${e}[2m  ${(r:iconw:: :):-VIA} $(printf '%-16s %4s  %-14s' PR AGE AUTHOR)  TITLE${e}[22m"
  print -r -- "	${e}[2m${(j: · :)st}${e}[22m"

  local gi head plain repo num title author at key note age reviewed icons
  local -a srcs
  for line in $rows; do
    IFS=$'\t' read -r gi u repo num title author at srcs reviewed <<<"$line"
    age=$(_z_age "$at")
    # Each icon is one cell (Nerd Font Mono); zsh counts the Nerd Font ones
    # as zero, so pad by the number of icons.
    icons="" srcs=(${(s:,:)srcs})
    for src in $srcs; do icons+="${ZSE_REQ_ICON[$src]:-?} "; done
    # First part of the login: katia-recard-taktile → katia
    author=${${${author%-taktile}#taktile-}%%[-._]*}
    head="  ${icons}${(l:iconw - 2 * $#srcs:: :)} $(printf '%-16s %4s  %-14s' "$(_z_repo_short "${repo#*/}")#$num" "$age" "${author[1,14]}")"
    key=$u note=""
    # New commits alone (no request) only count without a review session.
    [[ $srcs == rereview && -n ${sess[$u]:-} ]] && continue
    if [[ -n ${sess[$u]:-} ]]; then
      key=${sess[$u]}
      note="  → ${sess[$u]} (Enter switches)"
    elif [[ -n $reviewed ]]; then
      note="  reviewed $(_z_age "$reviewed") ago"
    fi
    plain=${head//$e\[[0-9;]#m/}
    rest=$((width - ${(m)#plain} - ${(m)#note} - 2 - ${#${(M)srcs:#(slack|linear|github|rereview)}}))
    ((rest > 0)) && head+="  ${title[1,rest]}"
    head+=$note
    if [[ -n $note ]]; then
      print -r -- "$key	${e}[2m${head//$e\[22m/}${e}[22m"
    else
      print -r -- "$key	$head"
    fi
  done
}

# zse pick — fzf over all sessions (Ctrl Space in Zellij); Enter switches
# (a stopped session is restored first), Ctrl-R reloads, Tab shows the
# review requests (Enter starts the review). The list cycles
# (down on the last row goes to the first). Group separators have an empty
# name: the cursor moves over them and Enter on one does nothing.
_zse_pick() {
  emulate -L zsh
  local choice key skip='[ -n {1} ] || echo'
  mkdir -p "$ZSE_REQ_DIR" && chmod 700 "$ZSE_REQ_DIR"
  # Sockets of pickers that did not close normally.
  rm -f "$ZSE_REQ_DIR"/fzf-*.sock(N=mh+12)
  local -x ZSE_FZF_SOCK="$ZSE_REQ_DIR/fzf-$$.sock"
  rm -f "$ZSE_FZF_SOCK"
  choice=$(COLUMNS=${COLUMNS:-$(tput cols 2>/dev/null)} _z_pick_lines \
    | fzf --ansi --delimiter=$'\t' --with-nth=2.. --layout=reverse --cycle \
    --listen-unsafe="$ZSE_FZF_SOCK" --track --id-nth=1 --header-lines=1 \
    --header="$(_z_pick_header)" \
    --preview="zsh -c 'source \"\$ZSE_SOURCE\"; _z_pick_preview \"\$1\"' zse {1}" \
    --preview-window='down,40%,wrap' \
    --bind="result:transform:$skip down" \
    --bind="down:down+transform:$skip down" \
    --bind="ctrl-j:down+transform:$skip down" \
    --bind="ctrl-n:down+transform:$skip down" \
    --bind="up:up+transform:$skip up" \
    --bind="ctrl-k:up+transform:$skip up" \
    --bind="ctrl-p:up+transform:$skip up" \
    --bind='enter:transform:[ -n {1} ] && echo accept' \
    --bind="tab:transform:$ZSE_ZCALL _z_req_toggle" \
    --bind="ctrl-r:transform:$ZSE_ZCALL _z_req_refresh")
  rm -f "$ZSE_FZF_SOCK"
  key=${choice%%$'\t'*}
  [[ -n $key ]] || return 0
  if [[ $key == https://* ]]; then
    zse -l review "$key"
  else
    _zse_switch "$key"
  fi
}

# ----- Commands -----

_zse_help() {
  cat <<'EOF'
usage:
  zse [-l USE_CASE] [-a AWS_PROFILE] [-t HINT] [NAME]
                                             start NAME, or attach if it runs
  zse ls                                     list registered and running sessions
  zse pick                                   pick a session with fzf (Ctrl Space)
  zse color [--all | NAME]                   set Claude's colour in running sessions
  zse stop [NAME | --all [--force]]          stop a session, keep it registered
  zse kill [NAME]                            end a session and clean up
  zse restore [NAME...]                      start stopped sessions in the background
  zse restart --all | NAME...                stop running sessions, start them again
  zse switch NAME                            switch to NAME (start it if stopped)
  zse migrate NAME... | --all [--force]      give old-style sessions the new names

  USE_CASE   code (default, or $ZSE_LAYOUT), project, ticket, review,
             review-doc, daily, explore, code-resume. A registered session
             keeps its use case.
  NAME       default: the current directory name; for `ticket`, the ticket ID;
             for `project` / `explore`, the slug; for `review`, a GitHub PR
             URL; for `review-doc`, a Notion URL or a GitHub PR URL.
             An existing session can also be named by its ticket ID or slug.
             stop / kill default to the current session.
  HINT       up to 3 short words in the name. Without -t, zse suggests one
             from the ticket / PR title (Claude, Haiku) and lets you edit it;
             -t '' means no hint.

  names      ticket tkt-<ID>-<hint>        review  rev-<repo>-<n>-<hint>
             project proj-<slug>           review-doc doc-<title>-<id8> / doc-<repo>-<n>
             explore exp-<slug>            code, daily: unchanged
             Worktree and branch keep the ticket ID / pr-<n> / slug.

  stop vs kill
    stop   Only stops the Zellij session. Its registry entry, worktree and
           Claude conversation stay: `zse NAME`, `zse switch NAME` or
           `zse restore` brings it back from the current layout and resumes
           the conversation.
    kill   Ends it: offers to remove its .claude/worktrees/<name> worktree,
           removes the AWS side-car, welcome sentinel and registry entry,
           then deletes the Zellij session.

  stop --all stops every running session except the current one, e.g.
  before a deploy that changes Zellij; `zse restore` brings them back. It
  skips sessions whose Claude is busy or waits for you, or that have
  background agents running; --force stops them too.

  activity (ls, pick) comes from `claude agents --json`:
    ● busy   ◐ waiting for you   ○ idle   · no Claude / unknown
  review state (ls, pick, tab name), from the review status pane:
    ✱ new: not reviewed yet, or new commits / comments since your review
    ↩ submitted (commented, changes requested)   ✔ approved
    ✗ closed   ⇥ merged
  pick lists reviews that need attention first in their group.

  colours: each type has a colour and four shades; a session gets the
  lowest free shade of its type (registry: shade) and a Zellij theme
  with it from the next start. A new conversation starts with Claude's
  /color for the type; `zse color` sets it in older ones (idle only).

  restore skips sessions that use -a (assume needs the YubiKey) and prints
  the command to start them.

  migrate renames sessions from before the name schema. The worktree, branch
  and Claude conversation stay. A running session is stopped and restored
  (it asks; --force does not); sessions with -a are not restored.

  restart picks up a new layout after a deploy: stop, then restore. It
  skips the current session (stopping it would end the command too);
  --all also skips sessions that use -a, so they keep running.
EOF
}

# zse [-l USE_CASE] [-a AWS_PROFILE] [-t HINT] [NAME] — start or attach.
#
# An existing session wins (`_z_resolve`: its name, a ticket ID, a project /
# explore slug; for a PR URL the session of that PR). A new session gets a
# name `<type>-<repo>-<id>-<hint>` and its name keys in the registry:
#   ticket      tkt-<ID>-<hint>          hint from the Linear title (Claude)
#   review      rev-<repo>-<n>-<hint>    hint from the PR title (Claude)
#   review-doc  doc-<title>-<id8> (Notion URL) / doc-<repo>-<n> (PR URL)
#   project     proj-<slug>
#   explore     exp-<slug>
# In a terminal zse shows the title and lets you edit the hint first;
# -t HINT skips Claude and the prompt (-t '' = no hint).
_zse_start() {
  emulate -L zsh
  local -A opts
  zparseopts -D -E -A opts l: a: t: || return 1
  # `name` may be inherited from a parent nix devShell (`name=nix-shell-env`);
  # `local` makes it function-scoped and the assignment reads $1 first.
  local name
  name="${1:-${PWD:t}}"
  [[ -z $name || $name == nix-shell-env ]] && name="zellij-$$"
  local use_case_opt=${opts[-l]:-}
  local uc=${use_case_opt:-${ZSE_LAYOUT:-code}}
  local has_hint=${+opts[-t]} hint_opt=${opts[-t]:-}

  local review_cwd="" url="" existing="" title="" hint=""
  local -A meta # name keys of a new session

  if [[ $name != http(s|)://* ]] && existing=$(_z_resolve "$name"); then
    name=$existing

  elif [[ ($uc == review || $uc == review-doc) \
    && $name =~ '^https?://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)' ]]; then
    # A GitHub PR URL: the session of that PR, started in ~/github/<owner>/<repo>.
    local owner=$match[1] repo=$match[2] pr=$match[3] old
    url=${name%%[?#]*}
    review_cwd="$HOME/github/$owner/$repo"
    if [[ $uc == review ]]; then old="review-$repo-pr$pr"; else old="review-doc-$repo-pr$pr"; fi
    local n
    for n in $(_z_reg_names); do
      if [[ $(_z_reg_get "$n" use_case) == $uc && $(_z_reg_get "$n" pr) == $pr \
        && $(_z_reg_get "$n" owner) == $owner && $(_z_reg_get "$n" repo) == $repo ]]; then
        existing=$n
        break
      fi
    done
    if [[ -n $existing ]]; then
      name=$existing
    elif _z_reg_get "$old" use_case >/dev/null 2>&1 || [[ $(_z_session_state "$old") != none ]]; then
      # A session from before the name schema. Its name has no owner: refuse
      # one for another checkout (alice/docs#1 vs bob/docs#1), which would
      # resume the other review in the other repo.
      local registered_dir
      registered_dir=$(_z_reg_get "$old" dir 2>/dev/null)
      if [[ -n $registered_dir && $registered_dir != $review_cwd ]]; then
        print -u2 -r "zse: session '$old' already belongs to $registered_dir."
        print -u2 -r "     Run 'zse kill $old' to end it before starting this one."
        return 1
      fi
      name=$old
    else
      if [[ ! -d $review_cwd/.git ]]; then
        print -u2 -r "zse: $review_cwd is not a git checkout. Clone $owner/$repo there first."
        return 1
      fi
      if [[ $uc == review ]]; then
        title=$(gh pr view "$pr" -R "$owner/$repo" --json title -q .title 2>/dev/null)
        if ((has_hint)); then
          hint=$(_z_hint_clean "$hint_opt")
        else
          [[ -n $title ]] && hint=$(_z_hint_ai "$title")
          _z_hint_ask "$owner/$repo#$pr" "$title" "$hint"
          hint=$REPLY
        fi
        name=$(_z_name rev "$(_z_repo_short "$repo")-$pr" "$hint")
      else
        name=$(_z_name doc "$(_z_repo_short "$repo")-$pr")
      fi
      meta=(names 2 owner "$owner" repo "$repo" pr "$pr" wt "pr-$pr" title "$title" hint "$hint")
    fi

  elif [[ $uc == review-doc && $name == http(s|)://* ]]; then
    # A Notion URL: `doc-<title>-<id8>`. The ID suffix makes names unique per
    # page; still refuse a registered session that belongs to another page
    # (or another URL when neither has an ID), because it would resume the
    # other review.
    url=$name
    local slug cand reg_url old_id new_id
    slug=$(_z_doc_slug "$url")
    for cand in "doc-$slug" "review-doc-$slug"; do
      reg_url=$(_z_reg_get "$cand" url 2>/dev/null) || continue
      old_id=$(_z_doc_page_id "$reg_url")
      new_id=$(_z_doc_page_id "$url")
      if [[ ${old_id:-${reg_url%%[?#]*}} != ${new_id:-${url%%[?#]*}} ]]; then
        print -u2 -r "zse: session '$cand' already reviews another doc: $reg_url"
        print -u2 -r "     Run 'zse kill $cand' to end that review, or start this one under another name."
        return 1
      fi
      existing=$cand
      break
    done
    if [[ -n $existing ]]; then
      name=$existing
    else
      name="doc-$slug"
      meta=(names 2 slug "$slug")
    fi

  elif [[ $uc == ticket && $name =~ '^[A-Za-z][A-Za-z0-9]*-[0-9]+$' ]]; then
    local id=${name:u}
    if ((has_hint)); then
      hint=$(_z_hint_clean "$hint_opt")
    else
      _z_ticket_info "$id"
      title=$REPLY
      _z_hint_ask "$id" "$title" "$REPLY_HINT"
      hint=$REPLY
    fi
    name=$(_z_name tkt "$id" "$hint")
    meta=(names 2 ticket "$id" wt "$id" title "$title" hint "$hint")

  elif [[ $uc == project || $uc == explore ]]; then
    local slug=${${name#proj-}#exp-}
    if [[ $uc == project ]]; then
      name="proj-$slug"
      meta=(names 2 slug "$slug")
    else
      name="exp-$slug"
      meta=(names 2 slug "$slug" wt "$slug")
    fi
  fi

  if [[ $(_z_session_state "$name") == live ]]; then
    if [[ -n ${opts[-a]:-} ]]; then
      local running
      running=$(sed -n 's/^AWS_PROFILE=//p' "$(_z_aws_sidecar "$name")" 2>/dev/null)
      print -u2 -r "zse: session '$name' already runs; -a ignored (session uses ${running:-<none>})."
    fi
    _z_aws_warn "$name"
    _z_attach "$name"
    return
  fi

  # Not running. A registered (stopped) session keeps its use case, start
  # directory and AWS profile unless overridden on the command line.
  local reg_uc reg_dir reg_aws
  if reg_uc=$(_z_reg_get "$name" use_case); then
    reg_dir=$(_z_reg_get "$name" dir)
    reg_aws=$(_z_reg_get "$name" aws_profile)
  fi
  local use_case=${use_case_opt:-${reg_uc:-${ZSE_LAYOUT:-code}}}
  local aws=${opts[-a]:-$reg_aws}
  local dir=${review_cwd:-${reg_dir:-$PWD}}
  if [[ ! -d $dir ]]; then
    print -u2 -r "zse: start directory $dir of '$name' no longer exists. Run 'zse kill $name', then start it again."
    return 1
  fi

  # Ticket / explore: create or reuse the worktree before claude starts
  # (`claude --worktree` reuses it as-is). A new branch starts at the fetched
  # origin default branch: ticket `<prefix>/<ID>` (`_z_ticket_worktree`),
  # explore `explore/<slug>`. Skipped outside a git repo.
  local root wt=${meta[wt]:-$(_z_worktree_name "$name")}
  if [[ $use_case == (ticket|explore) ]] && root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); then
    if [[ $use_case == ticket ]]; then
      _z_ticket_worktree "$root" "$wt" || return 1
    else
      _z_branch_worktree "$root" "$wt" "explore/$wt" || return 1
    fi
  fi

  # The panes read the name keys at start (`zse-meta`): register them first.
  if [[ -n $url ]] || ((${#meta})); then
    _z_reg_write "$name" "$use_case" "$dir" "$aws" "$url"
    local k
    for k in ${(k)meta}; do
      [[ -n ${meta[$k]} ]] && _z_reg_set "$name" "$k" "${meta[$k]}"
    done
  fi
  _z_launch "$name" "$use_case" "$dir" "$aws"
}

_zse_ls() {
  emulate -L zsh
  local -A zstate
  local line
  for line in ${(f)"$(zellij list-sessions --no-formatting 2>/dev/null)"}; do
    if [[ $line == *EXITED* ]]; then
      zstate[${line%% *}]=exited
    else
      zstate[${line%% *}]=live
    fi
  done

  _z_activity_load
  local fmt='%-40s %-12s %-10s %-16s %-14s %-4s %s\n'
  printf "$fmt" NAME USE_CASE STATE ACTIVITY REVIEW AWS DIR
  local n uc dir aws state act review
  for n in $(_z_reg_names); do
    uc=$(_z_reg_get "$n" use_case)
    dir=$(_z_reg_get "$n" dir)
    aws=$(_z_reg_get "$n" aws_profile)
    if [[ ${zstate[$n]:-} == live ]]; then
      state=running
    elif [[ ! -d $dir ]]; then
      state=orphan
    else
      state=stopped
    fi
    act=""
    [[ $state == running ]] && act="${ZSE_ACT_ICON[${ZSE_ACT[$n]:-?}]} $(_z_activity_word "$n")"
    review=""
    _z_review "$n" && review="${ZSE_REVIEW_MARK[$REPLY]:-?} $REPLY"
    # The name in the session's colour, padded first (escapes have no width).
    local shown=${(r:40:)n}
    [[ -t 1 ]] && shown=$'\e['"$(_z_sgr "$n" "$uc")m$shown"$'\e[0m'
    printf "%s ${fmt#%-40s }" "$shown" "$uc" "$state" "$act" "$review" "${aws:+yes}" "${dir/#$HOME/~}"
    unset "zstate[$n]"
  done
  # Sessions Zellij knows but the registry does not: started without zse,
  # or left over from before the registry.
  for n in ${(ko)zstate}; do
    if [[ ${zstate[$n]} == live ]]; then
      state=untracked
    else
      state=old-exited
    fi
    act=""
    [[ $state == untracked ]] && act="${ZSE_ACT_ICON[${ZSE_ACT[$n]:-?}]} $(_z_activity_word "$n")"
    printf "$fmt" "$n" "-" "$state" "$act" "" "" ""
  done
}

# _z_target NAME_OR_EMPTY — the session the given name refers to
# (`_z_resolve`: also a ticket ID or a project / explore slug), or the
# current session.
_z_target() {
  local name=${1:-${ZELLIJ_SESSION_NAME:-}}
  if [[ -z $name ]]; then
    print -u2 -r "zse: no session name given and not inside a Zellij session."
    return 1
  fi
  _z_resolve "$name" 2>/dev/null || print -r -- "$name"
}

# zse stop --all [--force] — stop every live session, registered or not
# (e.g. before a deploy that changes the Zellij version or socket dir).
# Skips the current session (stopping it would end this command too) and,
# without --force, every session whose Claude is busy or waiting for you or
# that has background agents running.
_zse_stop_all() {
  emulate -L zsh
  local force=${1:-} n skipped=0
  _z_activity_load
  for n in $(zellij list-sessions --no-formatting --short 2>/dev/null); do
    [[ $(_z_session_state "$n") == live ]] || continue
    if [[ -n ${ZELLIJ:-} && $n == "${ZELLIJ_SESSION_NAME:-}" ]]; then
      print -u2 -r "zse: '$n' is the current session — skipped. Run 'zse stop' in it, or 'zse stop --all' outside Zellij."
      continue
    fi
    if [[ -z $force ]] && _z_is_active "$n"; then
      print -u2 -r "zse: skipped '$n': $(_z_activity_word "$n")."
      ((skipped++))
      continue
    fi
    _zse_stop "$n"
  done
  ((skipped)) && print -u2 -r "zse: $skipped active session(s) kept running — 'zse stop --all --force' stops them too."
  return 0
}

_zse_stop() {
  emulate -L zsh
  if [[ ${1:-} == --all || ${1:-} == --force && ${2:-} == --all ]]; then
    if [[ ${1:-} == --force || ${2:-} == --force ]]; then
      _zse_stop_all --force
    else
      _zse_stop_all
    fi
    return
  fi
  local name
  name=$(_z_target "${1:-}") || return 1
  if ! _z_reg_get "$name" use_case >/dev/null; then
    print -u2 -r "zse: '$name' is not registered — 'zse restore' cannot bring it back."
  fi
  if [[ $(_z_session_state "$name") == none ]]; then
    print -r "zse: '$name' is not running."
    return 0
  fi
  zellij kill-session "$name"
}

_zse_kill() {
  emulate -L zsh
  local name
  name=$(_z_target "${1:-}") || return 1
  if ! _z_reg_get "$name" use_case >/dev/null && [[ $(_z_session_state "$name") == none ]]; then
    print -u2 -r "zse: no running or registered session '$name'."
    return 1
  fi

  # Repo root: the registered start dir, else the current repo.
  local root worktree reg_dir
  reg_dir=$(_z_reg_get "$name" dir 2>/dev/null)
  root=$(git -C "${reg_dir:-$PWD}" rev-parse --show-toplevel 2>/dev/null)
  [[ -n $root ]] && worktree="$root/.claude/worktrees/$(_z_worktree_name "$name")"

  # `review-<repo>-pr<n>` and `review-doc-<repo>-pr<n>` share the `pr-<n>`
  # worktree: keep it while another registered session still uses it.
  local other other_dir other_root
  if [[ -n $worktree && -d $worktree ]]; then
    for other in $(_z_reg_names); do
      [[ $other == $name ]] && continue
      other_dir=$(_z_reg_get "$other" dir 2>/dev/null)
      other_root=$(git -C "${other_dir:-/nonexistent}" rev-parse --show-toplevel 2>/dev/null)
      if [[ -n $other_root \
        && "$other_root/.claude/worktrees/$(_z_worktree_name "$other")" == $worktree ]]; then
        print -r "zse: keeping worktree $worktree — session '$other' also uses it."
        worktree=""
        break
      fi
    done
  fi

  if [[ -n $worktree && -d $worktree ]]; then
    printf 'zse: remove worktree %s? [y/N] ' "$worktree"
    local reply
    read -r reply
    if [[ $reply == [yY]* ]]; then
      _z_cleanup_worktree "$worktree" || return 1
    else
      print -r "zse: keeping worktree $worktree."
    fi
  fi

  rm -f "$ZSE_CACHE_DIR/$name.env" "$ZSE_CACHE_DIR/$name.welcomed" "$ZSE_CACHE_DIR/$name.claude-pane" "$(_z_reg_file "$name")" \
    "${XDG_CACHE_HOME:-$HOME/.cache}/zse/activity/$name.pr"
  # --force kills a running session first; also removes a leftover exited one.
  if [[ $(_z_session_state "$name") != none ]]; then
    zellij delete-session --force "$name" >/dev/null
  fi
  print -r "zse: killed '$name'."
}

_zse_restore() {
  emulate -L zsh
  local -a names
  if (($#)); then
    names=("$@")
  else
    names=($(_z_reg_names))
  fi
  local n uc dir aws started=0
  for n in $names; do
    if ! uc=$(_z_reg_get "$n" use_case); then
      print -u2 -r "zse: '$n' is not registered — skipped."
      continue
    fi
    [[ $(_z_session_state "$n") == live ]] && continue
    dir=$(_z_reg_get "$n" dir)
    aws=$(_z_reg_get "$n" aws_profile)
    if [[ ! -d $dir ]]; then
      print -u2 -r "zse: '$n': start directory $dir is gone — skipped (zse kill $n)."
      continue
    fi
    if [[ -n $aws ]]; then
      print -r "zse: '$n' uses AWS profile $aws — start it yourself: cd ${dir/#$HOME/~} && zse -l $uc -a $aws $n"
      continue
    fi
    _z_launch "$n" "$uc" "$dir" "" bg && {
      print -r "zse: started '$n' ($uc) in ${dir/#$HOME/~}"
      ((started++))
    }
  done
  ((started)) && print -r "zse: attach with 'zse <name>' or 'zse switch <name>'."
  return 0
}

# zse restart --all | NAME... — stop running sessions, then restore them
# from the current layout (e.g. after a deploy). Skips the current session:
# stopping it would end this command too. `--all` takes every running
# registered session except those with an AWS profile (restore cannot start
# them again); a named AWS session is stopped and restore prints its command.
_zse_restart() {
  emulate -L zsh
  local -a names todo
  local all=""
  if [[ ${1:-} == --all ]]; then
    all=1
    names=($(_z_reg_names))
  elif (($#)); then
    names=("$@")
  else
    print -u2 -r "zse: usage: zse restart --all | NAME..."
    return 1
  fi
  local n
  for n in $names; do
    if [[ -n ${ZELLIJ:-} && $n == "${ZELLIJ_SESSION_NAME:-}" ]]; then
      print -u2 -r "zse: '$n' is the current session — skipped. Run 'zse restart $n' from another session or outside Zellij."
      continue
    fi
    if ! _z_reg_get "$n" use_case >/dev/null; then
      print -u2 -r "zse: '$n' is not registered — skipped."
      continue
    fi
    [[ $(_z_session_state "$n") == live ]] || continue
    if [[ -n $all && -n $(_z_reg_get "$n" aws_profile) ]]; then
      print -r "zse: '$n' uses AWS — kept running. Restart it with 'zse restart $n'."
      continue
    fi
    zellij kill-session "$n" || continue
    # Wait until the server is gone, so restore does not attach to it.
    for _ in {1..20}; do
      [[ $(_z_session_state "$n") == none ]] && break
      sleep 0.25
    done
    todo+=("$n")
  done
  if ((!${#todo})); then
    print -r "zse: no running sessions to restart."
    return 0
  fi
  _zse_restore $todo
}

# _z_conv_id NAME DIR — the conversation ID zse-claude derives for a session
# without a `conv` key (keep in sync with zseClaude in zellij.nix).
_z_conv_id() {
  local h
  h=$(printf 'zse:%s:%s' "$1" "$2" | shasum -a 256 | cut -c1-32)
  print -r -- "${h[1,8]}-${h[9,12]}-5${h[14,16]}-8${h[18,20]}-${h[21,32]}"
}

# zse migrate NAME... | --all [--force] — give sessions from before the name
# schema a new name and the name keys (see _zse_start). The worktree, branch
# and Claude conversation stay: `conv` keeps the conversation ID derived from
# the old name. A running session is stopped first (asks; --force does not)
# and restored under the new name; sessions with -a are not restored.
_zse_migrate() {
  emulate -L zsh
  local force="" all=""
  local -a names
  while (($#)); do
    case $1 in
      --force) force=1 ;;
      --all) all=1 ;;
      *) names+=("$1") ;;
    esac
    shift
  done
  if [[ -n $all ]]; then
    names=($(_z_reg_names))
  elif ((!${#names})); then
    print -u2 -r "zse: usage: zse migrate NAME... | --all [--force]"
    return 1
  fi

  local n uc dir aws new title hint live repo pr owner conv cand d k reply
  local -A meta
  for n in $names; do
    uc=$(_z_reg_get "$n" use_case) || { print -u2 -r "zse: '$n' is not registered — skipped."; continue; }
    [[ -n $(_z_reg_get "$n" names) ]] && { [[ -z $all ]] && print -r "zse: '$n' already uses the name schema."; continue; }
    dir=$(_z_reg_get "$n" dir)
    aws=$(_z_reg_get "$n" aws_profile)
    title="" hint="" meta=()
    case $uc in
      ticket)
        if [[ ! $n =~ '^[A-Za-z][A-Za-z0-9]*-[0-9]+$' ]]; then
          print -r "zse: '$n' is not a ticket ID — skipped."
          continue
        fi
        _z_ticket_info "${n:u}"
        title=$REPLY
        _z_hint_ask "$n" "$title" "$REPLY_HINT"
        hint=$REPLY
        new=$(_z_name tkt "${n:u}" "$hint")
        meta=(ticket "${n:u}" wt "$n" title "$title" hint "$hint")
        ;;
      review | review-doc)
        if [[ $n =~ '^review(-doc)?-(.+)-pr([0-9]+)$' ]]; then
          repo=$match[2] pr=$match[3] owner=${${dir:h}:t}
          if [[ $uc == review ]]; then
            title=$(gh pr view "$pr" -R "$owner/$repo" --json title -q .title 2>/dev/null)
            [[ -n $title ]] && hint=$(_z_hint_ai "$title")
            _z_hint_ask "$owner/$repo#$pr" "$title" "$hint"
            hint=$REPLY
            new=$(_z_name rev "$(_z_repo_short "$repo")-$pr" "$hint")
            _z_reg_set "$n" url "https://github.com/$owner/$repo/pull/$pr"
          else
            new=$(_z_name doc "$(_z_repo_short "$repo")-$pr")
          fi
          meta=(owner "$owner" repo "$repo" pr "$pr" wt "pr-$pr" title "$title" hint "$hint")
        elif [[ $uc == review-doc && $n == review-doc-* ]]; then
          new="doc-${n#review-doc-}"
          meta=(slug "${n#review-doc-}")
        else
          print -r "zse: '$n' has no PR or doc in its name — skipped."
          continue
        fi
        ;;
      project) new="proj-$n" meta=(slug "$n") ;;
      explore) new="exp-$n" meta=(slug "$n" wt "$n") ;;
      *)
        [[ -z $all ]] && print -r "zse: '$n' ($uc) keeps its name."
        continue
        ;;
    esac
    if [[ $new == $n ]]; then
      _z_reg_set "$n" names 2
      continue
    fi
    if _z_reg_get "$new" use_case >/dev/null 2>&1 || [[ $(_z_session_state "$new") != none ]]; then
      print -u2 -r "zse: '$new' exists already — '$n' skipped."
      continue
    fi

    # The conversation zse-claude resumed under the old name: the ID from the
    # registered dir, or from its physical path when that is the one with a
    # transcript.
    conv=$(_z_conv_id "$n" "$dir")
    for d in "$dir" "${dir:A}"; do
      cand=$(_z_conv_id "$n" "$d")
      if [[ -n $(print -l "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$cand".jsonl(N)) ]]; then
        conv=$cand
        break
      fi
    done

    live=""
    if [[ $(_z_session_state "$n") == live ]]; then
      if [[ -n ${ZELLIJ:-} && $n == "${ZELLIJ_SESSION_NAME:-}" ]]; then
        print -u2 -r "zse: '$n' is the current session — skipped. Run 'zse migrate $n' from another session or outside Zellij."
        continue
      fi
      if [[ -z $force ]]; then
        if [[ ! -t 0 ]]; then
          print -u2 -r "zse: '$n' is running — skipped (--force stops it)."
          continue
        fi
        ((${+ZSE_ACT})) || _z_activity_load
        if _z_is_active "$n"; then
          print -u2 -r "zse: skipped '$n': $(_z_activity_word "$n") (--force stops it)."
          continue
        fi
        printf "zse: '%s' is running. Stop it, rename it to '%s' and restore it? [y/N] " "$n" "$new"
        read -r reply
        [[ $reply == [yY]* ]] || { print -r "zse: '$n' skipped."; continue; }
      fi
      zellij kill-session "$n" || continue
      for _ in {1..20}; do
        [[ $(_z_session_state "$n") == none ]] && break
        sleep 0.25
      done
      live=1
    fi
    [[ $(_z_session_state "$n") == exited ]] && zellij delete-session "$n" >/dev/null 2>&1

    mv "$(_z_reg_file "$n")" "$(_z_reg_file "$new")" || continue
    [[ -e $ZSE_CACHE_DIR/$n.env ]] && mv "$ZSE_CACHE_DIR/$n.env" "$ZSE_CACHE_DIR/$new.env"
    [[ -e $ZSE_CACHE_DIR/$n.welcomed ]] && mv "$ZSE_CACHE_DIR/$n.welcomed" "$ZSE_CACHE_DIR/$new.welcomed"
    rm -f "$ZSE_CACHE_DIR/$n.claude-pane"
    local act_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zse/activity"
    [[ -e $act_dir/$n.pr ]] && mv "$act_dir/$n.pr" "$act_dir/$new.pr"
    for k in ${(k)meta}; do
      [[ -n ${meta[$k]} ]] && _z_reg_set "$new" "$k" "${meta[$k]}"
    done
    _z_reg_set "$new" conv "$conv"
    _z_reg_set "$new" names 2
    print -r "zse: '$n' → '$new'"
    if [[ -n $live ]]; then
      if [[ -n $aws ]]; then
        print -r "zse: '$new' uses AWS profile $aws — start it yourself: zse $new"
      else
        _zse_restore "$new"
      fi
    fi
  done
}

# zse color [--all | NAME] — set Claude's prompt-bar colour (`/color`) in
# running sessions whose conversation started before #42 phase 3 (new ones
# get it from zse-claude). Types `/color <c>` into the claude pane (ID from
# zse-claude) only when that Claude is idle; others are skipped with the
# reason. The transcript keeps the colour, so once is enough.
_zse_color() {
  emulate -L zsh
  local -a targets
  if [[ ${1:-} == --all ]]; then
    targets=($(_z_reg_names))
  else
    targets=("$(_z_target "${1:-}")") || return 1
  fi
  _z_activity_load
  local n uc c pid
  for n in $targets; do
    [[ $(_z_session_state "$n") == live ]] || { [[ ${1:-} == --all ]] || print -u2 -r "zse: '$n' is not running."; continue; }
    uc=$(_z_reg_get "$n" use_case 2>/dev/null)
    c=${ZSE_CLAUDE_COLOR[$uc]:-}
    [[ -n $c ]] || { [[ ${1:-} == --all ]] || print -u2 -r "zse: '$n' ($uc) has no Claude colour."; continue; }
    pid=""
    [[ -r $ZSE_CACHE_DIR/$n.claude-pane ]] && pid=$(<"$ZSE_CACHE_DIR/$n.claude-pane")
    if [[ -z $pid ]]; then
      print -u2 -r "zse: skipped '$n': no claude pane ID — 'zse restart $n' (it then gets the colour on its next new conversation, or run 'zse color $n' after)."
      continue
    fi
    if [[ ${ZSE_ACT[$n]:-} != idle ]]; then
      print -u2 -r "zse: skipped '$n': Claude is $(_z_activity_word "$n")."
      continue
    fi
    zellij --session "$n" action write-chars --pane-id "$pid" "/color $c" &&
      sleep 0.3 &&
      zellij --session "$n" action send-keys --pane-id "$pid" Enter &&
      print -r "zse: '$n' → $c"
  done
  return 0
}

_zse_switch() {
  emulate -L zsh
  local name=${1:-}
  if [[ -z $name ]]; then
    print -u2 -r "zse: usage: zse switch NAME"
    return 1
  fi
  name=$(_z_resolve "$name" 2>/dev/null || print -r -- "$name")
  if [[ $(_z_session_state "$name") != live ]]; then
    if ! _z_reg_get "$name" use_case >/dev/null; then
      print -u2 -r "zse: no running or registered session '$name'."
      return 1
    fi
    if [[ -n $(_z_reg_get "$name" aws_profile) ]]; then
      print -u2 -r "zse: '$name' uses AWS — start it with 'zse $name' (assume needs the YubiKey)."
      return 1
    fi
    _zse_restore "$name" >/dev/null || return 1
  fi
  _z_attach "$name"
}

zse() {
  case ${1:-} in
    ls) shift; _zse_ls "$@" ;;
    stop) shift; _zse_stop "$@" ;;
    kill) shift; _zse_kill "$@" ;;
    restore) shift; _zse_restore "$@" ;;
    restart) shift; _zse_restart "$@" ;;
    switch) shift; _zse_switch "$@" ;;
    migrate) shift; _zse_migrate "$@" ;;
    pick) shift; _zse_pick "$@" ;;
    color) shift; _zse_color "$@" ;;
    -h | --help | help) _zse_help ;;
    --) shift; _zse_start "$@" ;;
    *) _zse_start "$@" ;;
  esac
}

# ----- Deprecated aliases (remove in a later release) -----

zsek() {
  if [[ ${1:-} == -k ]]; then
    print -u2 "zsek -k is deprecated: use 'zse stop'."
    _zse_stop
  else
    print -u2 "zsek is deprecated: use 'zse kill' (or 'zse stop' to keep the session)."
    _zse_kill
  fi
}
zss() {
  print -u2 "zss is deprecated: use 'zse switch'."
  _zse_switch "$@"
}
zsep() {
  print -u2 "zsep is deprecated: use 'zse -l code-resume NAME'."
  _zse_start -l code-resume "$@"
}

# ----- Completion -----

# Running sessions plus registered ones.
_zse_names() {
  local -a names
  names=(${(u)${(f)"$(zellij list-sessions --short 2>/dev/null; _z_reg_names)"}})
  _describe -t sessions 'zse session' names
}

_zse() {
  local -a verbs
  verbs=(
    'ls:list registered and running sessions'
    'pick:pick a session with fzf'
    'color:set Claude colour in running sessions'
    'stop:stop a session, keep it registered'
    'kill:end a session and clean up'
    'restore:start stopped sessions in the background'
    'restart:stop running sessions and start them again'
    'switch:switch to a session'
    'migrate:give old-style sessions the new names'
    'help:show usage'
  )
  case ${words[2]:-} in
    color)
      ((CURRENT == 3)) && compadd -- --all
      ((CURRENT >= 3)) && _zse_names
      return
      ;;
    kill | switch | restore)
      ((CURRENT >= 3)) && _zse_names
      return
      ;;
    stop)
      ((CURRENT >= 3)) && compadd -- --all --force
      ((CURRENT >= 3)) && _zse_names
      return
      ;;
    restart)
      ((CURRENT == 3)) && compadd -- --all
      ((CURRENT >= 3)) && _zse_names
      return
      ;;
    migrate)
      ((CURRENT >= 3)) && compadd -- --all --force
      ((CURRENT >= 3)) && _zse_names
      return
      ;;
    ls | pick | help) return ;;
  esac
  ((CURRENT == 2)) && _describe -t verbs 'zse command' verbs
  _arguments \
    '-l[layout / use case]:use case:(code project ticket review review-doc daily explore code-resume)' \
    '-a[AWS profile]:profile:' \
    '-t[hint in the name]:hint:' \
    '*:session name:_zse_names'
}

if (( $+functions[compdef] )); then
  compdef _zse zse
  compdef _zse_names zss
fi
