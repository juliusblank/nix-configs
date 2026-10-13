{ pkgs, ... }:

let
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
    Right-hand column shared by `code`, `project.master` and `ticket`:
    shell on top, tig status view below. tig only refreshes on user action,
    so this pane stays quiet (no periodic SSH-agent prompts).
  */
  shellTigColumn = ''
    pane split_direction="horizontal" {
        pane name="shell"
        pane name="git" {
            command "tig"
            args "status"
        }
    }
  '';

  /**
    Three-pane body — claude on the left, shellTigColumn on the right —
    the shape shared by `code`, `project.master` and `ticket`. `claudePane`
    is the full pane node for the Claude command (different per layout).
  */
  threePaneBody = claudePane: ''
    pane split_direction="vertical" {
        ${claudePane}
        ${shellTigColumn}
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

  codeClaudePane = ''
    pane name="claude" {
        command "claude"
        args "--continue"
    }
  '';

  codeResumeClaudePane = ''
    pane name="claude" {
        command "claude"
        args "--resume"
    }
  '';

  # ticket and review read `$ZELLIJ_SESSION_NAME`, which Zellij sets per
  # pane at session creation (verified in the installed binary). No layout
  # rendering needed — multiple concurrent ticket/review sessions each see
  # their own session name.
  ticketClaudePane = ''
    pane name="claude" {
        command "sh"
        args "-c" "exec claude --worktree \"$ZELLIJ_SESSION_NAME\""
    }
  '';

  reviewClaudePane = ''
    pane name="claude" {
        command "sh"
        args "-c" "exec claude \"/review $ZELLIJ_SESSION_NAME\""
    }
  '';

in
{
  # Zellij terminal multiplexer — one session per project / Claude workflow.
  #
  # Four use-case layouts (see docs/usage/zellij.md for the long form):
  #
  #   code     — default. claude --continue · shell · tig status · status bar.
  #   project  — tabs: master (code shape, --continue) + full-screen
  #              `claude agents`. Status via `default_tab_template`.
  #   ticket   — `claude --worktree $ZELLIJ_SESSION_NAME` · shell · tig.
  #              Session name is the ticket ID; worktree is created / reused
  #              at `.claude/worktrees/<id>`.
  #   review   — fresh `claude "/review $ZELLIJ_SESSION_NAME"` · shell
  #              (no tig). Session name is the PR number convention
  #              (`pr-<n>`). The `review` skill (in taktile-skills) handles
  #              checkout; without it, the first message appears as literal
  #              text.
  #
  # `code-resume` is a `--resume`-picker variant used by `zrp`.
  #
  # Zsh integration stays off deliberately — auto-attach misbehaves inside
  # Claude Code's PTY and nested shells.
  programs.zellij = {
    enable = true;
    enableZshIntegration = false;
    settings = {
      default_shell = "zsh";
      theme = "ghostty-0x96f";
      pane_frames = false;
      copy_command = "pbcopy";
      scroll_buffer_size = 50000;
    };
  };

  home = {
    packages = [ pkgs.tig ];

    file = {
      # ----- Use-case layouts -----

      ".config/zellij/layouts/code.kdl".text = mkSingleTreeLayout (threePaneBody codeClaudePane);

      ".config/zellij/layouts/code-resume.kdl".text = mkSingleTreeLayout (
        threePaneBody codeResumeClaudePane
      );

      ".config/zellij/layouts/ticket.kdl".text = mkSingleTreeLayout (threePaneBody ticketClaudePane);

      # Review has no tig pane — just claude + shell + status bar.
      ".config/zellij/layouts/review.kdl".text = mkSingleTreeLayout ''
        pane split_direction="vertical" {
            ${reviewClaudePane}
            pane name="shell"
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
                ${threePaneBody codeClaudePane}
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
      # Shipped as a separate theme file so `programs.zellij.settings.theme`
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

    # Path of the per-session AWS side-car (if any). Only written when `zr`
    # is invoked with `-a`; otherwise absent. Stores AWS_PROFILE +
    # AWS_SESSION_EXPIRATION so later attaches can warn on expiry.
    _z_aws_sidecar() {
      printf '%s/zr/sessions/%s.env' "''${XDG_CACHE_HOME:-$HOME/.cache}" "$1"
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
        print -u2 -r "zr: ⚠ session '$name' AWS creds (profile '$profile') expired at $exp — re-authenticate."
      elif (( remaining <= 900 )); then
        print -u2 -r "zr: ⚠ session '$name' AWS creds (profile '$profile') expire in $(( remaining / 60 ))m — re-authenticate soon."
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

      local status
      status=$( cd "$worktree" 2>/dev/null && git status --porcelain 2>/dev/null )
      if [[ -n $status ]]; then
        print -u2 -r "zrk: worktree $worktree has uncommitted changes — skipping removal."
        return 1
      fi
      local upstream unpushed
      upstream=$( cd "$worktree" && git rev-parse --abbrev-ref '@{u}' 2>/dev/null )
      if [[ -n $upstream ]]; then
        unpushed=$( cd "$worktree" && git rev-list "''${upstream}..HEAD" 2>/dev/null )
        if [[ -n $unpushed ]]; then
          print -u2 -r "zrk: worktree $worktree has unpushed commits on $upstream — skipping removal."
          return 1
        fi
      fi

      local common_dir repo_root
      common_dir=$( cd "$worktree" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null )
      repo_root="''${common_dir%/.git}"
      [[ -d $repo_root ]] || {
        print -u2 -r "zrk: cannot resolve parent repo for $worktree."
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
      print -r "zrk: removed worktree $worktree"
    }

    # ----- Public commands -----

    # zr [-l USE_CASE] [-a AWS_PROFILE] [NAME]
    #
    #   USE_CASE  — one of `code`, `project`, `ticket`, `review`. Defaults
    #               to $ZR_LAYOUT if set (so devshells can bind a layout
    #               per repo), else `code`.
    #   AWS_PROF  — binds an AWS profile to the session by launching Zellij
    #               through the host's `assume` fn (`aws-vault exec` on
    #               concinnity, YubiKey TOTP, 8h). The AWS profile and
    #               expiration are side-car'd at ~/.cache/zr/sessions/<name>.env
    #               so later attaches warn on near / past expiry.
    #   NAME      — session name. Defaults to basename of $PWD. For `ticket`,
    #               pass the ticket ID; for `review`, pass `pr-<n>`. ticket
    #               and review layouts read the name via $ZELLIJ_SESSION_NAME
    #               so no layout rendering is involved.
    #
    # Session state matrix:
    #   live       → attach (ignore -a with a one-line warning)
    #   exited     → attach — Zellij resurrects the serialized layout and
    #                cwds. Processes start fresh (claude's --continue picks
    #                up the conversation; ticket's --worktree reuses).
    #   none       → create a fresh session with the chosen layout.
    zr() {
      emulate -L zsh
      local -A opts
      zparseopts -D -E -A opts l: a: || return 1
      local use_case="''${opts[-l]:-''${ZR_LAYOUT:-code}}"
      local aws_profile="''${opts[-a]:-}"
      local name="''${1:-$(basename "$PWD")}"
      local sidecar
      sidecar=$(_z_aws_sidecar "$name")

      if _z_session_exists "$name"; then
        if [[ -n $aws_profile ]]; then
          local existing shown
          existing=$(sed -n 's/^AWS_PROFILE=//p' "$sidecar" 2>/dev/null)
          shown=''${existing:-<none>}
          print -u2 -r "zr: session '$name' already exists; -a ignored (session uses $shown)."
        fi
        _z_aws_warn "$name"
        zellij attach "$name"
        return
      fi

      if [[ -n $aws_profile ]]; then
        mkdir -p "''${sidecar%/*}"
        # Hand off to the host's `assume` fn; the inner shell writes the
        # side-car with the credentials it just got, then execs zellij so
        # every pane inherits them.
        assume "$aws_profile" -- zsh -c '
          printf "AWS_PROFILE=%s\nAWS_SESSION_EXPIRATION=%s\n" \
            "$AWS_PROFILE" "$AWS_SESSION_EXPIRATION" > "$1"
          exec zellij -s "$2" -n "$3"
        ' zr-aws "$sidecar" "$name" "$use_case"
      else
        zellij -s "$name" -n "$use_case"
      fi
    }

    # zrp [NAME] — like zr but uses the `code-resume` layout, which opens
    # Claude's --resume picker over conversations in cwd instead of
    # auto-continuing the most recent. For non-code use cases a resume
    # picker doesn't apply (ticket reuses its worktree; review is fresh;
    # project's agent dispatcher is live) — stay on `zr`.
    zrp() {
      emulate -L zsh
      local name="''${1:-$(basename "$PWD")}"
      if _z_session_exists "$name"; then
        _z_aws_warn "$name"
        zellij attach "$name"
      else
        zellij -s "$name" -n code-resume
      fi
    }

    # zrk — kill the current Zellij session and clean up after it.
    #
    # For sessions whose name matches a `.claude/worktrees/<name>` worktree
    # under the current repo (the ticket / review convention), zrk prompts,
    # then removes the worktree + its auto-created branch when the tree is
    # clean and fully pushed. Uncommitted or unpushed state blocks removal
    # with a message explaining why.
    #
    # Also deletes the AWS side-car for the session.
    zrk() {
      emulate -L zsh
      local name="''${ZELLIJ_SESSION_NAME:-}"
      if [[ -z $name ]]; then
        print -u2 -r "zrk: not inside a Zellij session (ZELLIJ_SESSION_NAME is empty)."
        return 1
      fi

      local root worktree
      if root=$(git rev-parse --show-toplevel 2>/dev/null); then
        worktree="$root/.claude/worktrees/$name"
      fi

      if [[ -n $worktree && -d $worktree ]]; then
        printf 'zrk: remove worktree %s? [y/N] ' "$worktree"
        local reply
        read -r reply
        if [[ $reply == y* || $reply == Y* ]]; then
          _z_cleanup_worktree "$worktree" || return 1
        else
          print -r "zrk: keeping worktree $worktree."
        fi
      fi

      local sidecar
      sidecar=$(_z_aws_sidecar "$name")
      rm -f "$sidecar"

      zellij kill-session "$name"
    }

    # ----- Completion -----

    # _zr completes `-l` with the known use cases and `-a` with AWS profile
    # names (reusing the host-defined `_aws_profile_completions` on
    # concinnity; on other hosts `-a` falls through to no completion).
    _zr() {
      _arguments \
        '-l[layout / use-case]:use case:(code project ticket review)' \
        '-a[AWS profile]:profile:' \
        ':session name:'
    }
    compdef _zr zr zrp
  '';
}
