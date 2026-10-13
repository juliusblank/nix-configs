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

  # `claude --worktree $ZR_SESSION_NAME` — reuses an existing worktree with
  # the same name, creates one otherwise (Phase 1 verified both branches).
  # Routed through `sh -c` so `$ZR_SESSION_NAME` is expanded at pane start.
  # Note: Zellij 0.43 inherits env vars at *server* startup, not per session,
  # so the second ticket/review session on an existing server may not see a
  # fresh value — PR 2's `zr` works around this by rendering the layout to a
  # temp file with the name baked in.
  ticketClaudePane = ''
    pane name="claude" {
        command "sh"
        args "-c" "exec claude --worktree \"$ZR_SESSION_NAME\""
    }
  '';

  # Fresh claude session (no `--continue`) that opens with `/review <pr>` as
  # its first user message. $ZR_SESSION_NAME is the PR number convention
  # (`pr-<n>`); the `review` skill (lives in taktile-skills, not in-repo yet)
  # strips the prefix. If the skill is not installed, Claude Code shows the
  # literal command and the user can type the prompt manually.
  reviewClaudePane = ''
    pane name="claude" {
        command "sh"
        args "-c" "exec claude \"/review $ZR_SESSION_NAME\""
    }
  '';

in
{
  # Zellij terminal multiplexer — one session per project / Claude workflow.
  #
  # The repo recognises four use-case layouts:
  #
  #   code     — default. claude --continue · shell · tig status · status bar.
  #              The shape current `zr` sessions use today.
  #   project  — long-running "master" plan + a tab that owns `claude agents`
  #              for dispatching parallel ticket sub-sessions. Two tabs:
  #                master: claude --continue · shell · tig
  #                agents: full-screen `claude agents`
  #              Status bar via `default_tab_template` so both tabs get it.
  #   ticket   — single-ticket work in its own worktree. Starts
  #              `claude --worktree $ZR_SESSION_NAME` where NAME is the
  #              ticket ID; worktree lives at `.claude/worktrees/<id>`.
  #              Pane shape otherwise matches `code`.
  #   review   — short-lived PR review. Fresh claude (no --continue) opens
  #              with `/review <pr>` as its first message; no tig pane.
  #              The `review` skill handles the PR checkout.
  #
  # Backwards-compat aliases `repo` and `repo-resume` point at `code` and
  # `code-resume`; the `zr` / `zrp` zsh fns still invoke those names until
  # PR 2 switches them to the new interface.
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

      # ----- Compat aliases (removed in PR 2 once zr/zrp switch to new names) -----

      ".config/zellij/layouts/repo.kdl".text = mkSingleTreeLayout (threePaneBody codeClaudePane);
      ".config/zellij/layouts/repo-resume.kdl".text = mkSingleTreeLayout (
        threePaneBody codeResumeClaudePane
      );

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
    # Internal: does a session with NAME exist, live or resurrectable?
    # `list-sessions -s` lists live sessions only; the unflagged form also
    # includes exited sessions that Zellij has serialized to disk and can
    # resurrect. Strip ANSI colouring (Zellij emits it even when piped) and
    # take the first field as the session name.
    _z_session_exists() {
      zellij list-sessions 2>/dev/null \
        | sed 's/\x1b\[[0-9;]*m//g' \
        | cut -d' ' -f1 \
        | grep -qx "$1"
    }

    # zr [NAME] — attach, resurrect, or create a Zellij session with the
    # "repo" layout. NAME defaults to the current directory basename, so
    # `zr` from a repo root gives a session named after the repo.
    #
    # PR 2 of the use-case-layouts series will rewrite this to accept
    # `-l USE_CASE` / `-a AWS_PROFILE` and dispatch to `code`, `project`,
    # `ticket` or `review`. Until then `zr` and `zrp` still use the
    # `repo` / `repo-resume` compat layouts.
    #
    # Behaviour by session state:
    #   live       → attach
    #   exited     → attach (Zellij resurrects the serialized layout and
    #                cwds; processes start fresh — claude's `--continue`
    #                in the layout picks up where the conversation was)
    #   none       → create a new session with the "repo" layout
    #
    # Zellij 0.43 note: `-l/--layout` with `-s/--session` means "add this
    # layout as a new tab in an *existing* session". The flag that starts
    # a new session with a layout is `-n/--new-session-with-layout`, so
    # the create branch below uses that.
    zr() {
      local name="''${1:-$(basename "$PWD")}"
      if _z_session_exists "$name"; then
        zellij attach "$name"
      else
        zellij -s "$name" -n repo
      fi
    }

    # zrp [NAME] — like zr, but the Claude pane runs `claude --resume`,
    # which opens the picker over conversations in the current directory.
    # Use when the cwd has multiple past conversations and you want to
    # pick one explicitly instead of auto-resuming the most recent.
    #
    # Resurrection uses the serialized layout, not the one named here, so
    # `zrp <name>` on an exited session resurrects whatever layout it had.
    zrp() {
      local name="''${1:-$(basename "$PWD")}"
      if _z_session_exists "$name"; then
        zellij attach "$name"
      else
        zellij -s "$name" -n repo-resume
      fi
    }
  '';
}
