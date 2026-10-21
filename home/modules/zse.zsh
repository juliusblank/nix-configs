# zse — Zellij session CLI for Claude Code workflows.
#
# Sourced from ~/.zshrc by home/modules/zellij.nix. Docs: docs/usage/zellij.md.
#
#   zse [-l USE_CASE] [-a AWS_PROFILE] [NAME]   start or attach
#   zse ls                                      registry + live state
#   zse stop [NAME]                             stop, keep registered
#   zse kill [NAME]                             end: worktree prompt, cleanup, unregister
#   zse restore [NAME…]                         start stopped sessions in the background
#   zse switch NAME                             switch to a session (start it if stopped)
#
# Zellij session serialization is off (config.kdl). The registry below is the
# record of which sessions exist; each session is always (re)created from the
# current layout file, and `zse-claude --own` resumes its own conversation.

typeset -g ZSE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zse/sessions"
typeset -g ZSE_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zse/sessions"

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

# _z_reg_write NAME USE_CASE DIR AWS_PROFILE — keeps `created`, sets `last_started`.
_z_reg_write() {
  local f now created
  f=$(_z_reg_file "$1")
  now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  created=$(_z_reg_get "$1" created 2>/dev/null)
  mkdir -p "$ZSE_STATE_DIR"
  printf 'use_case=%s\ndir=%s\naws_profile=%s\ncreated=%s\nlast_started=%s\n' \
    "$2" "$3" "$4" "${created:-$now}" "$now" >"$f"
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

# Worktree dir name for a session: review sessions are `review-<repo>-pr<n>`,
# but /review:review checks the PR out into `.claude/worktrees/pr-<n>`.
_z_worktree_name() {
  if [[ $1 =~ '^review-.+-pr([0-9]+)$' ]]; then
    print -r -- "pr-$match[1]"
  else
    print -r -- "$1"
  fi
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

# Attach to a running session; inside Zellij, switch in place instead of
# nesting a client.
_z_attach() {
  if [[ -n ${ZELLIJ:-} ]]; then
    zellij action switch-session "$1"
  else
    zellij attach "$1"
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
  (
    # -q: no chpwd hooks. direnv's hook would export the devshell's
    # `name=nix-shell-env` over our local `name`. The panes load the devshell
    # themselves (`zse-env`, home/modules/zellij.nix).
    cd -q "$dir" || exit 1
    if [[ -n $bg ]]; then
      zellij attach --create-background "$name" options --default-layout "$use_case"
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
        exec zellij -s "$2" -n "$3"
      ' zse-aws "$sidecar" "$name" "$use_case"
    else
      zellij -s "$name" -n "$use_case"
    fi
  ) || return
  [[ -n $switch ]] && zellij action switch-session "$name"
  return 0
}

# ----- Commands -----

_zse_help() {
  cat <<'EOF'
usage:
  zse [-l USE_CASE] [-a AWS_PROFILE] [NAME]  start NAME, or attach if it runs
  zse ls                                     list registered and running sessions
  zse stop [--all | NAME]                    stop a session, keep it registered
  zse kill [NAME]                            end a session and clean up
  zse restore [NAME...]                      start stopped sessions in the background
  zse restart --all | NAME...                stop running sessions, start them again
  zse switch NAME                            switch to NAME (start it if stopped)

  USE_CASE   code (default, or $ZSE_LAYOUT), project, ticket, review, daily,
             explore, code-resume. A registered session keeps its use case.
  NAME       default: the current directory name; for `review`, a GitHub PR URL.
             stop / kill default to the current session.

  stop vs kill
    stop   Only stops the Zellij session. Its registry entry, worktree and
           Claude conversation stay: `zse NAME`, `zse switch NAME` or
           `zse restore` brings it back from the current layout and resumes
           the conversation.
    kill   Ends it: offers to remove its .claude/worktrees/<name> worktree,
           removes the AWS side-car, welcome sentinel and registry entry,
           then deletes the Zellij session.

  stop --all stops every running session except the current one, e.g.
  before a deploy that changes Zellij; `zse restore` brings them back.

  restore skips sessions that use -a (assume needs the YubiKey) and prints
  the command to start them.

  restart picks up a new layout after a deploy: stop, then restore. It
  skips the current session (stopping it would end the command too);
  --all also skips sessions that use -a, so they keep running.
EOF
}

# zse [-l USE_CASE] [-a AWS_PROFILE] [NAME] — start or attach.
_zse_start() {
  emulate -L zsh
  local -A opts
  zparseopts -D -E -A opts l: a: || return 1
  # `name` may be inherited from a parent nix devShell (`name=nix-shell-env`);
  # `local` makes it function-scoped and the assignment reads $1 first.
  local name
  name="${1:-${PWD:t}}"
  [[ -z $name || $name == nix-shell-env ]] && name="zellij-$$"

  # Review mode: a GitHub PR URL becomes `review-<repo>-pr<n>`, started in
  # the matching checkout at ~/github/<owner>/<repo>.
  local review_cwd=""
  local use_case_opt=${opts[-l]:-}
  if [[ ${use_case_opt:-${ZSE_LAYOUT:-code}} == review \
    && $name =~ '^https?://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)' ]]; then
    local owner=$match[1] repo=$match[2] pr=$match[3]
    name="review-$repo-pr$pr"
    review_cwd="$HOME/github/$owner/$repo"
    if [[ ! -d $review_cwd/.git ]]; then
      print -u2 -r "zse: $review_cwd is not a git checkout. Clone $owner/$repo there first."
      return 1
    fi
  fi

  if [[ $(_z_session_state "$name") == live ]]; then
    if [[ -n ${opts[-a]:-} ]]; then
      local existing
      existing=$(sed -n 's/^AWS_PROFILE=//p' "$(_z_aws_sidecar "$name")" 2>/dev/null)
      print -u2 -r "zse: session '$name' already runs; -a ignored (session uses ${existing:-<none>})."
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

  # Ticket / explore mode: pre-create the worktree on branch
  # `$ZSE_BRANCH_USER/<ticket>` (ticket) or `explore/<slug>` (explore) instead
  # of Claude Code's default `worktree-<name>`; `claude --worktree` reuses an
  # existing worktree as-is. Skipped outside a git repo, when the worktree
  # exists, or for ticket when ZSE_BRANCH_USER is empty.
  local wt_prefix=""
  case $use_case in
    ticket) [[ -n ${ZSE_BRANCH_USER:-} ]] && wt_prefix="$ZSE_BRANCH_USER" ;;
    explore) wt_prefix="explore" ;;
  esac
  if [[ -n $wt_prefix ]]; then
    local repo_root
    if repo_root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); then
      local worktree_dir="$repo_root/.claude/worktrees/$name"
      if [[ ! -d $worktree_dir ]]; then
        local branch="$wt_prefix/$name"
        mkdir -p "$repo_root/.claude/worktrees"
        if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then
          git -C "$repo_root" worktree add "$worktree_dir" "$branch" >/dev/null || return 1
        else
          git -C "$repo_root" worktree add -b "$branch" "$worktree_dir" >/dev/null || return 1
        fi
      fi
    fi
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

  local fmt='%-36s %-12s %-10s %-4s %s\n'
  printf "$fmt" NAME USE_CASE STATE AWS DIR
  local n uc dir aws state
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
    printf "$fmt" "$n" "$uc" "$state" "${aws:+yes}" "${dir/#$HOME/~}"
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
    printf "$fmt" "$n" "-" "$state" "" ""
  done
}

# _z_target NAME_OR_EMPTY — the given name, or the current session.
_z_target() {
  local name=${1:-${ZELLIJ_SESSION_NAME:-}}
  if [[ -z $name ]]; then
    print -u2 -r "zse: no session name given and not inside a Zellij session."
    return 1
  fi
  print -r -- "$name"
}

# zse stop --all — stop every live session, registered or not (e.g. before
# a deploy that changes the Zellij version or socket dir). Skips the current
# session: stopping it would end this command too.
_zse_stop_all() {
  emulate -L zsh
  local n
  for n in $(zellij list-sessions --no-formatting --short 2>/dev/null); do
    [[ $(_z_session_state "$n") == live ]] || continue
    if [[ -n ${ZELLIJ:-} && $n == "${ZELLIJ_SESSION_NAME:-}" ]]; then
      print -u2 -r "zse: '$n' is the current session — skipped. Run 'zse stop' in it, or 'zse stop --all' outside Zellij."
      continue
    fi
    _zse_stop "$n"
  done
}

_zse_stop() {
  emulate -L zsh
  if [[ ${1:-} == --all ]]; then
    _zse_stop_all
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

  rm -f "$ZSE_CACHE_DIR/$name.env" "$ZSE_CACHE_DIR/$name.welcomed" "$(_z_reg_file "$name")"
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

_zse_switch() {
  emulate -L zsh
  local name=${1:-}
  if [[ -z $name ]]; then
    print -u2 -r "zse: usage: zse switch NAME"
    return 1
  fi
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
    'stop:stop a session, keep it registered'
    'kill:end a session and clean up'
    'restore:start stopped sessions in the background'
    'restart:stop running sessions and start them again'
    'switch:switch to a session'
    'help:show usage'
  )
  case ${words[2]:-} in
    kill | switch | restore)
      ((CURRENT >= 3)) && _zse_names
      return
      ;;
    stop | restart)
      ((CURRENT == 3)) && compadd -- --all
      ((CURRENT >= 3)) && _zse_names
      return
      ;;
    ls | help) return ;;
  esac
  ((CURRENT == 2)) && _describe -t verbs 'zse command' verbs
  _arguments \
    '-l[layout / use case]:use case:(code project ticket review daily explore code-resume)' \
    '-a[AWS profile]:profile:' \
    '*:session name:_zse_names'
}

if (( $+functions[compdef] )); then
  compdef _zse zse
  compdef _zse_names zss
fi
