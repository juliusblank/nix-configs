{ pkgs, ... }:

let
  # ----- Welcome banner script -----

  /**
    Prints a one-time welcome in a `ticket` / `project` / `review` shell pane.
    First invocation per Zellij session writes a sentinel at
    `~/.cache/zse/sessions/<name>.welcomed`; subsequent attaches skip the
    banner. `zsek` deletes the sentinel along with the AWS side-car.
  */
  zseWelcome = pkgs.writeShellScriptBin "zse-welcome" ''
    #!/bin/sh
    set -eu
    use_case="''${1:-}"
    name="''${ZELLIJ_SESSION_NAME:-}"
    [ -n "$use_case" ] || exit 0
    [ -n "$name" ] || exit 0

    # Rename the current Zellij tab to a human-friendly label where we can
    # derive one from the session name. Review sessions carry
    # `review-<repo>-pr<n>`; map that back to `[review] <repo> PR #<n>`.
    # Ticket / project sessions already look clean, so just prefix the tag.
    # Run on every pane start — Zellij ignores a rename-tab call whose
    # target already matches, so this is cheap and idempotent.
    case "$use_case" in
      review)
        case "$name" in
          review-*-pr*)
            repo=''${name#review-}
            repo=''${repo%-pr*}
            pr=''${name##*-pr}
            zellij action rename-tab "[review] $repo PR #$pr" 2>/dev/null || true
            ;;
          *)
            zellij action rename-tab "[review] $name" 2>/dev/null || true
            ;;
        esac
        ;;
      ticket)
        zellij action rename-tab "[ticket] $name" 2>/dev/null || true
        ;;
      project)
        zellij action rename-tab "[project] $name" 2>/dev/null || true
        ;;
    esac

    dir="''${XDG_CACHE_HOME:-$HOME/.cache}/zse/sessions"
    sentinel="$dir/$name.welcomed"
    [ -f "$sentinel" ] && exit 0
    mkdir -p "$dir"
    : > "$sentinel"

    case "$use_case" in
      ticket)
        cat <<'ART'
    ┏━━━━━━━━━━━┓
    ┃  TICKET   ┃
    ┗━━━━━━━━━━━┛
    ART
        printf '→ /ticket:start %s — prime ticket context (jbl-personal/ticket)\n' "$name"
        ;;
      project)
        cat <<'ART'
    ┏━━━━━━━━━━━┓
    ┃  PROJECT  ┃
    ┗━━━━━━━━━━━┛
    ART
        printf '→ /project:start %s — bootstrap master session (jbl-personal/project)\n' "$name"
        ;;
      review)
        cat <<'ART'
    ┏━━━━━━━━━━━┓
    ┃  REVIEW   ┃
    ┗━━━━━━━━━━━┛
    ART
        printf '→ /review:review %s is auto-sent in the claude pane (jbl-personal/review)\n' "$name"
        ;;
      *)
        exit 0
        ;;
    esac
  '';

  # ----- Shared pane fragments -----

  /**
    Status-bar pane inline in a layout's own pane tree. Used by layouts that
    do not define explicit `tab {}` blocks — `default_tab_template` only
    fires for those, so single-pane-tree layouts need the plugin pane
    declared directly.
  */
  statusBarPane = ''
    pane size=2 borderless=true {
        plugin location="zellij:status-bar"
    }
  '';

  /**
    Shell pane. When `useCase` is non-null (ticket / project / review), the
    pane runs `zse-welcome <useCase>` on first open to show a 3-line banner
    + one-line hint, then execs zsh. For `code` / `code-resume` the pane is
    plain zsh — no welcome, no indirection.
  */
  mkShellPane =
    useCase:
    if useCase == null then
      ''pane name="shell"''
    else
      ''
        pane name="shell" {
            command "zsh"
            args "-ic" "zse-welcome ${useCase}; exec zsh"
        }
      '';

  /**
    Right-hand column shared by `code`, `project.master` and `ticket`:
    shell on top, tig status view below. tig only refreshes on user action,
    so this pane stays quiet (no periodic SSH-agent prompts).
  */
  shellTigColumn = useCase: ''
    pane split_direction="horizontal" {
        ${mkShellPane useCase}
        pane name="git" {
            command "tig"
            args "status"
        }
    }
  '';

  /**
    Three-pane body — claude on the left, shellTigColumn on the right —
    the shape shared by `code`, `project.master` and `ticket`. `claudePane`
    is the full pane node for the Claude command (different per layout);
    `useCase` toggles the shell-pane welcome.
  */
  threePaneBody = useCase: claudePane: ''
    pane split_direction="vertical" {
        ${claudePane}
        ${shellTigColumn useCase}
    }
  '';

  /**
    Wrap a pane tree in a single-pane-tree layout with the inline status bar
    underneath. Used by `code`, `code-resume`, `ticket` and `review`.
    `project` uses `default_tab_template` instead and does not wrap here.
  */
  mkSingleTreeLayout = body: ''
    layout {
        pane split_direction="horizontal" {
            ${body}
            ${statusBarPane}
        }
    }
  '';

  # ----- Per-layout Claude panes -----

  /**
    `zse-claude [--own] [CLAUDE_ARGS…]` — the claude launcher for every
    interactive zse pane.

    Always adds `--remote-control "$ZELLIJ_SESSION_NAME"` (reachable from the
    account's other Remote-Control devices under the Zellij session's name)
    and `--name "$ZELLIJ_SESSION_NAME"` (shown in the prompt box, `/resume`
    picker and terminal title).

    `--own` gives the Zellij session its own conversation. The ID is a UUID
    derived from the session name and the pane's start directory, so it is
    stable across pane restarts and session resurrection. If a transcript
    with that ID exists, resume it; otherwise start a fresh conversation
    under that ID. `claude --continue` is not used: it resumes the most
    recent conversation in the directory, so two zse sessions in the same
    repo (e.g. a `code` session and a new `project` master) would share one
    conversation. `--resume <id>` also works when the conversation's cwd is
    a worktree (ticket), because the lookup is by ID.
  */
  zseClaude = pkgs.writeShellScriptBin "zse-claude" ''
    set -euo pipefail
    name=''${ZELLIJ_SESSION_NAME:?zse-claude: run inside a Zellij session}
    base=(--remote-control "$name" --name "$name")

    if [[ ''${1:-} != --own ]]; then
      exec claude "''${base[@]}" "$@"
    fi
    shift

    h=$(printf 'zse:%s:%s' "$name" "$PWD" | shasum -a 256 | cut -c1-32)
    id="''${h:0:8}-''${h:8:4}-5''${h:13:3}-8''${h:17:3}-''${h:20:12}"

    shopt -s nullglob
    transcripts=("''${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$id".jsonl)
    if ((''${#transcripts[@]})); then
      exec claude "''${base[@]}" --resume "$id" "$@"
    fi
    exec claude "''${base[@]}" --session-id "$id" "$@"
  '';

  /**
    Interactive claude pane for a use case. It exports `ZSE_USE_CASE=<useCase>`
    (plugins key off it: the jbl-personal `project` plugin's SessionStart
    hook injects the master-session ground rules) and runs `zse-claude` with
    `args` (already KDL-string-escaped). One shell wraps the exec so
    `$ZELLIJ_SESSION_NAME`, which Zellij sets per pane at session creation,
    interpolates at pane start — ticket / review sessions share one layout
    file and each sees its own name.
  */
  mkClaudePane = useCase: args: ''
    pane name="claude" {
        command "sh"
        args "-c" "export ZSE_USE_CASE=${useCase}; exec ${zseClaude}/bin/zse-claude ${args}"
    }
  '';

  codeClaudePane = mkClaudePane "code" "--own";
  codeResumeClaudePane = mkClaudePane "code" "--resume";
  projectClaudePane = mkClaudePane "project" "--own";
  dailyClaudePane = mkClaudePane "daily" "--own";
  ticketClaudePane = mkClaudePane "ticket" ''--own --worktree \"$ZELLIJ_SESSION_NAME\"'';
  # Explicit namespace (`/review:review`) over the shorthand (`/review`) so
  # the command stays unambiguous as more plugins add their own `review`.
  reviewClaudePane = mkClaudePane "review" ''\"/review:review $ZELLIJ_SESSION_NAME\"'';

  /**
    Task-list pane for the `daily` layout. Runs the repo's own
    `scripts/tasks-pane` (the daily-tasks fzf picker: open tasks across all
    daily notes, keys to tick / drop). The script owns all vault logic; this
    layout only places it. Falls back to a hint + plain zsh when the script
    is missing, so the layout still opens in any repo.
  */
  tasksPane = ''
    pane name="tasks" size="40%" {
        command "sh"
        args "-c" "[ -x scripts/tasks-pane ] && exec scripts/tasks-pane; echo 'zse daily: no executable scripts/tasks-pane in this repo'; exec zsh"
    }
  '';

in
{
  # Zellij terminal multiplexer — one session per project / Claude workflow.
  #
  # Use-case layouts (see docs/usage/zellij.md for the long form):
  #
  #   code     — default. claude --continue · shell · tig status · status bar.
  #   project  — tabs: master (code shape, --continue) + full-screen
  #              `claude agents`. Status via `default_tab_template`. Master
  #              shell shows a one-time `/project:start` welcome banner.
  #   ticket   — `claude --worktree $ZELLIJ_SESSION_NAME` · shell · tig.
  #              Session name is the ticket ID; worktree is created / reused
  #              at `.claude/worktrees/<id>`. Shell shows a one-time
  #              `/ticket:start` welcome banner.
  #   review   — fresh `claude "/review:review $ZELLIJ_SESSION_NAME"` · shell
  #              (no tig). Session name is `review-<repo>-pr<n>`, parsed
  #              from a PR URL. The review command auto-fires in the claude
  #              pane; the shell shows a one-time banner noting that.
  #   daily    — claude --continue · tasks pane (`scripts/tasks-pane` from
  #              the daily-tasks repo: fzf over open tasks, tick in place).
  #
  # Welcome banners are a one-shot per session — a sentinel at
  # `~/.cache/zse/sessions/<name>.welcomed` suppresses the banner on resume.
  # `zsek` deletes the sentinel so a reused session name re-welcomes.
  #
  # `code-resume` is a `--resume`-picker variant used by `zsep`.
  #
  # Zsh integration stays off deliberately — auto-attach misbehaves inside
  # Claude Code's PTY and nested shells.
  programs.zellij = {
    enable = true;
    enableZshIntegration = false;
    # Config is written out of band at `.config/zellij/config.kdl` below so we
    # can carry a `keybinds` block (the `settings` → KDL converter does not
    # cleanly model Zellij's `bind "<key>" { Action "arg" { attr v; } }`
    # shape; a hand-written KDL fragment is simpler and surfaces changes
    # right in the diff).
  };

  home = {
    packages = [
      pkgs.tig
      zseWelcome
      zseClaude
    ];

    file = {
      # ----- Config -----

      # Flat KDL — same base as what `programs.zellij.settings` used to emit,
      # plus a `shared` keybind that opens the Session Manager picker in one
      # keystroke (`Ctrl Space`) instead of the three-step dance through
      # Zellij's default session mode. `Ctrl Space` is unused by zsh at the
      # prompt and by every other Zellij default binding, and reads as
      # "activate the switcher".
      ".config/zellij/config.kdl".text = ''
        copy_command "pbcopy"
        default_shell "zsh"
        pane_frames false
        scroll_buffer_size 50000
        theme "ghostty-0x96f"
        keybinds {
            shared {
                bind "Ctrl Space" { LaunchOrFocusPlugin "session-manager" { floating true; }; SwitchToMode "Normal"; }
            }
        }
      '';

      # ----- Use-case layouts -----

      ".config/zellij/layouts/code.kdl".text = mkSingleTreeLayout (threePaneBody null codeClaudePane);

      ".config/zellij/layouts/code-resume.kdl".text = mkSingleTreeLayout (
        threePaneBody null codeResumeClaudePane
      );

      ".config/zellij/layouts/ticket.kdl".text = mkSingleTreeLayout (
        threePaneBody "ticket" ticketClaudePane
      );

      # Review has no tig pane — just claude + shell + status bar.
      ".config/zellij/layouts/review.kdl".text = mkSingleTreeLayout ''
        pane split_direction="vertical" {
            ${reviewClaudePane}
            ${mkShellPane "review"}
        }
      '';

      # Daily: claude + the daily-tasks task picker. No shell / tig — the
      # vault is committed by `/eod`, and ticks happen in the tasks pane.
      ".config/zellij/layouts/daily.kdl".text = mkSingleTreeLayout ''
        pane split_direction="vertical" {
            ${dailyClaudePane}
            ${tasksPane}
        }
      '';

      # Project uses `default_tab_template` so the status bar renders in both
      # tabs. `focus=true` on master makes it the default on session open.
      ".config/zellij/layouts/project.kdl".text = ''
        layout {
            default_tab_template {
                children
                ${statusBarPane}
            }
            tab name="master" focus=true {
                ${threePaneBody "project" projectClaudePane}
            }
            tab name="agents" {
                pane {
                    command "claude"
                    args "agents"
                }
            }
        }
      '';

      # ----- Theme -----

      # Zellij theme matched to the Ghostty "0x96f" theme (see home/ghostty.nix).
      # Shipped as a separate theme file so the `theme` line in config.kdl
      # above just needs to name it.
      ".config/zellij/themes/ghostty-0x96f.kdl".text = ''
        themes {
            ghostty-0x96f {
                fg "#FFFFFF"
                bg "#262427"
                black "#434343"
                red "#FF2740"
                green "#ABE047"
                yellow "#FFC24B"
                blue "#51A5FA"
                magenta "#FF75B5"
                cyan "#35BBB0"
                white "#FFFFFF"
                orange "#FFC24B"
            }
        }
      '';
    };
  };

  programs.zsh.initContent = ''
    # ----- Internal helpers -----

    # Does a session with NAME exist, live or resurrectable? Unflagged
    # `list-sessions` includes exited (serialized) sessions; strip ANSI
    # colouring (Zellij emits it even when piped) and take the first field.
    _z_session_exists() {
      zellij list-sessions 2>/dev/null \
        | sed 's/\x1b\[[0-9;]*m//g' \
        | cut -d' ' -f1 \
        | grep -qx "$1"
    }

    # Path of the per-session AWS side-car (if any). Only written when `zse`
    # is invoked with `-a`; otherwise absent. Stores AWS_PROFILE +
    # AWS_SESSION_EXPIRATION so later attaches can warn on expiry.
    _z_aws_sidecar() {
      printf '%s/zse/sessions/%s.env' "''${XDG_CACHE_HOME:-$HOME/.cache}" "$1"
    }

    # Warn on stdout if the serialized expiry is within 15 min or past.
    # Silently removes the side-car if the session no longer exists.
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
      exp_epoch=$(date -jf '%Y-%m-%dT%H:%M:%SZ' "''${exp%+00:00}Z" '+%s' 2>/dev/null) \
        || exp_epoch=$(date -jf '%Y-%m-%dT%H:%M:%SZ' "$exp" '+%s' 2>/dev/null) \
        || return 0
      now_epoch=$(date '+%s')
      remaining=$(( exp_epoch - now_epoch ))
      if (( remaining <= 0 )); then
        print -u2 -r "zse: ⚠ session '$name' AWS creds (profile '$profile') expired at $exp — re-authenticate."
      elif (( remaining <= 900 )); then
        print -u2 -r "zse: ⚠ session '$name' AWS creds (profile '$profile') expire in $(( remaining / 60 ))m — re-authenticate soon."
      fi
    }

    # Clean up a `.claude/worktrees/<name>` worktree if it exists and is safe:
    # no uncommitted changes, no unpushed commits (relative to its upstream).
    # Prints the reason it skipped on stderr. Also deletes the auto-created
    # `worktree-<name>` branch that `claude --worktree` leaves behind.
    _z_cleanup_worktree() {
      emulate -L zsh
      local worktree="$1" wt_name="''${1##*/}"
      [[ -d $worktree ]] || return 0

      # `status` is a read-only built-in in zsh (holds $?) — use `dirty`.
      local dirty
      dirty=$( cd "$worktree" 2>/dev/null && git status --porcelain 2>/dev/null )
      if [[ -n $dirty ]]; then
        print -u2 -r "zsek: worktree $worktree has uncommitted changes — skipping removal."
        return 1
      fi
      local upstream unpushed
      upstream=$( cd "$worktree" && git rev-parse --abbrev-ref '@{u}' 2>/dev/null )
      if [[ -n $upstream ]]; then
        unpushed=$( cd "$worktree" && git rev-list "''${upstream}..HEAD" 2>/dev/null )
        if [[ -n $unpushed ]]; then
          print -u2 -r "zsek: worktree $worktree has unpushed commits on $upstream — skipping removal."
          return 1
        fi
      fi

      local common_dir repo_root
      common_dir=$( cd "$worktree" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null )
      repo_root="''${common_dir%/.git}"
      [[ -d $repo_root ]] || {
        print -u2 -r "zsek: cannot resolve parent repo for $worktree."
        return 1
      }

      (
        cd "$repo_root" || exit 1
        # `claude --worktree` locks the worktree; `unlock` fails silently
        # when it's already unlocked, so we don't gate on its exit code.
        git worktree unlock "$worktree" 2>/dev/null
        git worktree remove "$worktree" || exit 1
        git worktree prune 2>/dev/null
        git branch -D "worktree-$wt_name" 2>/dev/null
      ) || return 1
      print -r "zsek: removed worktree $worktree"
    }

    # ----- Public commands -----

    # zse [-l USE_CASE] [-a AWS_PROFILE] [NAME]
    #
    #   USE_CASE  — one of `code`, `project`, `ticket`, `review`, `daily`. Defaults
    #               to $ZSE_LAYOUT if set (so devshells can bind a layout
    #               per repo), else `code`.
    #   AWS_PROF  — binds an AWS profile to the session by launching Zellij
    #               through the host's `assume` fn (`aws-vault exec` on
    #               concinnity, YubiKey TOTP, 8h). The AWS profile and
    #               expiration are side-car'd at ~/.cache/zse/sessions/<name>.env
    #               so later attaches warn on near / past expiry.
    #   NAME      — session name. Defaults to basename of $PWD. For `ticket`,
    #               pass the ticket ID; for `review`, pass a PR URL. ticket
    #               and review layouts read the name via $ZELLIJ_SESSION_NAME
    #               so no layout rendering is involved.
    #
    # Session state matrix:
    #   live       → attach (ignore -a with a one-line warning)
    #   exited     → attach — Zellij resurrects the serialized layout and
    #                cwds. Processes start fresh (claude's --continue picks
    #                up the conversation; ticket's --worktree reuses).
    #   none       → create a fresh session with the chosen layout.
    zse() {
      emulate -L zsh
      local -A opts
      zparseopts -D -E -A opts l: a: || return 1
      local use_case="''${opts[-l]:-''${ZSE_LAYOUT:-code}}"
      local aws_profile="''${opts[-a]:-}"
      # `name` may be inherited from a parent nix devShell as the exported
      # `name=nix-shell-env` default. `local` declares the var function-scoped
      # (`emulate -L zsh` keeps the usual semantics) and the assignment then
      # reads $1 — never the inherited value — before falling back to the
      # cwd's basename, which is sane for every non-review use case.
      local name
      name="''${1:-$(basename "$PWD")}"
      [[ -z $name || $name == nix-shell-env ]] && name="zellij-$$"
      local tab_name=""
      local sidecar
      sidecar=$(_z_aws_sidecar "$name")

      # Review mode: accept a GitHub PR URL as NAME. Extract the PR number
      # and set the session name to `review-<repo>-pr<n>` so the Zellij
      # session list, the AWS side-car, the welcome sentinel and (when
      # `/review:review $ZELLIJ_SESSION_NAME` fires in the layout) the
      # checked-out worktree all carry the repo + PR context in one glance.
      # The matching local checkout is at ~/github/<owner>/<repo>; zellij is
      # launched from there so `.claude/worktrees/pr-<n>` resolves inside
      # the right repo. Non-review use cases keep the plain `basename $PWD`
      # default. `tab_name` carries the human-friendly label for the tab
      # bar; applied via `zellij action rename-tab` after the session is up.
      local review_cwd=""
      if [[ $use_case == review && $name =~ '^https?://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)' ]]; then
        local owner=$match[1] repo=$match[2] pr=$match[3]
        name="review-$repo-pr$pr"
        tab_name="[review] $repo PR #$pr"
        review_cwd="$HOME/github/$owner/$repo"
        if [[ ! -d $review_cwd/.git ]]; then
          print -u2 -r "zse: $review_cwd is not a git checkout. Clone $owner/$repo there first."
          return 1
        fi
        sidecar=$(_z_aws_sidecar "$name")
      fi

      if _z_session_exists "$name"; then
        if [[ -n $aws_profile ]]; then
          local existing shown
          existing=$(sed -n 's/^AWS_PROFILE=//p' "$sidecar" 2>/dev/null)
          shown=''${existing:-<none>}
          print -u2 -r "zse: session '$name' already exists; -a ignored (session uses $shown)."
        fi
        _z_aws_warn "$name"
        zellij attach "$name"
        return
      fi

      # Ticket mode: pre-create the Claude Code worktree on branch
      # `$ZSE_BRANCH_USER/<ticket>` instead of letting Claude Code default to
      # `worktree-<ticket>`. Claude's `--worktree <name>` reuses an existing
      # `.claude/worktrees/<name>` directory as-is, so creating it ahead of
      # time with the branch we want is a no-op for Claude and spares us the
      # rename-after-the-fact step. Skipped silently when:
      #   - cwd is not inside a git repo (`zse -l ticket` from ~, etc.)
      #   - the worktree directory already exists (idempotent)
      #   - `ZSE_BRANCH_USER` is empty (fall back to Claude's default)
      if [[ $use_case == ticket && -n ''${ZSE_BRANCH_USER:-} ]]; then
        local repo_root
        if repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
          local worktree_dir="$repo_root/.claude/worktrees/$name"
          if [[ ! -d $worktree_dir ]]; then
            local branch="$ZSE_BRANCH_USER/$name"
            mkdir -p "$repo_root/.claude/worktrees"
            if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then
              git -C "$repo_root" worktree add "$worktree_dir" "$branch" >/dev/null || return 1
            else
              git -C "$repo_root" worktree add -b "$branch" "$worktree_dir" >/dev/null || return 1
            fi
          fi
        fi
      fi

      # Subshell so the `cd` for review mode never leaks into the caller.
      (
        [[ -n $review_cwd ]] && { cd "$review_cwd" || exit 1; }
        if [[ -n $aws_profile ]]; then
          mkdir -p "''${sidecar%/*}"
          # Hand off to the host's `assume` fn; the inner shell writes the
          # side-car with the credentials it just got, then execs zellij so
          # every pane inherits them.
          assume "$aws_profile" -- zsh -c '
            printf "AWS_PROFILE=%s\nAWS_SESSION_EXPIRATION=%s\n" \
              "$AWS_PROFILE" "$AWS_SESSION_EXPIRATION" > "$1"
            exec zellij -s "$2" -n "$3"
          ' zse-aws "$sidecar" "$name" "$use_case"
        else
          zellij -s "$name" -n "$use_case"
        fi
      )
    }

    # zsep [NAME] — like zse but uses the `code-resume` layout, which opens
    # Claude's --resume picker over conversations in cwd instead of
    # auto-continuing the most recent. For non-code use cases a resume
    # picker doesn't apply (ticket reuses its worktree; review is fresh;
    # project's agent dispatcher is live) — stay on `zse`.
    zsep() {
      emulate -L zsh
      local name="''${1:-$(basename "$PWD")}"
      if _z_session_exists "$name"; then
        _z_aws_warn "$name"
        zellij attach "$name"
      else
        zellij -s "$name" -n code-resume
      fi
    }

    # zsek — kill the current Zellij session and clean up after it.
    #
    # For sessions whose name matches a `.claude/worktrees/<name>` worktree
    # under the current repo (the ticket / review convention), zsek prompts,
    # then removes the worktree + its auto-created branch when the tree is
    # clean and fully pushed. Uncommitted or unpushed state blocks removal
    # with a message explaining why.
    #
    # Also deletes the AWS side-car and the welcome sentinel so a reused
    # session name re-welcomes.
    zsek() {
      emulate -L zsh
      local name="''${ZELLIJ_SESSION_NAME:-}"
      if [[ -z $name ]]; then
        print -u2 -r "zsek: not inside a Zellij session (ZELLIJ_SESSION_NAME is empty)."
        return 1
      fi

      local root worktree
      if root=$(git rev-parse --show-toplevel 2>/dev/null); then
        worktree="$root/.claude/worktrees/$name"
      fi

      if [[ -n $worktree && -d $worktree ]]; then
        printf 'zsek: remove worktree %s? [y/N] ' "$worktree"
        local reply
        read -r reply
        if [[ $reply == y* || $reply == Y* ]]; then
          _z_cleanup_worktree "$worktree" || return 1
        else
          print -r "zsek: keeping worktree $worktree."
        fi
      fi

      local dir
      dir="''${XDG_CACHE_HOME:-$HOME/.cache}/zse/sessions"
      rm -f "$dir/$name.env" "$dir/$name.welcomed"

      zellij kill-session "$name"
    }

    # zss NAME — switch the current Zellij session in place to a different
    # live/exited session without detaching. Faster than `Ctrl Space, pick`
    # when you already know the target name (`zss <TAB>` completes with the
    # live session list via `_zse_sessions`).
    zss() {
      emulate -L zsh
      if [[ -z $1 ]]; then
        print -u2 -r "zss: usage: zss <session-name>"
        return 1
      fi
      zellij action switch-session "$1"
    }

    # ----- Completion -----

    # Session names from `zellij list-sessions` for the positional NAME on
    # `zse` / `zsep` / `zss`. Strips Zellij's ANSI colour and the trailing
    # `(EXITED - attach to resurrect)` / `(current)` marker.
    _zse_sessions() {
      local -a sessions
      sessions=(''${(f)"$(zellij list-sessions 2>/dev/null \
        | sed 's/\x1b\[[0-9;]*m//g' \
        | awk '{print $1}')"})
      _describe -t sessions 'zellij session' sessions
    }

    # _zse completes `-l` with the known use cases and the positional NAME
    # with live Zellij sessions. `-a` takes a profile name but has no
    # completion yet.
    _zse() {
      _arguments \
        '-l[layout / use-case]:use case:(code project ticket review daily)' \
        '-a[AWS profile]:profile:' \
        ':session name:_zse_sessions'
    }
    compdef _zse zse zsep
    compdef _zse_sessions zss
  '';
}
