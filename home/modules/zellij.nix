{ pkgs, ... }:

let
  # ----- Welcome banner script -----

  /**
    Prints a one-time welcome in a `ticket` / `project` / `review` shell pane.
    First invocation per Zellij session writes a sentinel at
    `~/.cache/zse/sessions/<name>.welcomed`; subsequent attaches skip the
    banner. `zse kill` deletes the sentinel along with the AWS side-car.
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
    Compact bar inline in a layout's own pane tree: one row with the session
    name, the tabs (active one highlighted) and the current mode. Replaces
    the two-row `status-bar`, which shows key hints but no tabs — so the
    `project` layout's `master` / `agents` tabs were invisible. Layouts
    without explicit `tab {}` blocks declare it directly;
    `default_tab_template` only fires for layouts with tabs.
  */
  barPane = ''
    pane size=1 borderless=true {
        plugin location="zellij:compact-bar"
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
    `zse-git [USE_CASE]` — the git pane. For `ticket` it waits (up to 30 s)
    for the session's worktree at `.claude/worktrees/<id>`, then shows only
    the ticket's commits: `tig <origin default branch>..HEAD` (origin, so a
    stale local `main` does not skew it). Every other use case shows
    `tig status` at the pane's directory. Refresh comes from tig's periodic
    mode (`~/.config/tig/config` below) — local `git status` only, never a
    fetch, so no SSH-agent / 1Password prompts.
  */
  zseGit = pkgs.writeShellScriptBin "zse-git" ''
    set -uo pipefail
    if [[ ''${1:-} == ticket ]]; then
      name=''${ZELLIJ_SESSION_NAME:?zse-git: run inside a Zellij session}
      root=$(git rev-parse --show-toplevel 2>/dev/null) || exec tig status
      wt="$root/.claude/worktrees/$name"
      for _ in $(seq 1 30); do
        [[ -d $wt ]] && break
        sleep 1
      done
      if [[ ! -d $wt ]]; then
        echo "zse-git: $wt not found after 30 s; showing repo status instead"
        sleep 2
        exec tig status
      fi
      cd "$wt" || exit 1
      base=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
      exec tig "$base..HEAD"
    fi
    exec tig status
  '';

  /**
    `zse-ci` — the CI pane of the `review` layout. Reads the PR number from
    the `review-<repo>-pr<n>` session name and redraws `gh pr checks <n>`
    with the PR title every `$ZSE_CI_INTERVAL` seconds (default 30), so new
    pushes show up too. `gh` talks HTTPS with its own token — no SSH. `q`
    quits; the command pane then waits for Enter to restart it.
  */
  zseCi = pkgs.writeShellScriptBin "zse-ci" ''
    set -uo pipefail
    name=''${ZELLIJ_SESSION_NAME:-}
    if [[ ! $name =~ -pr([0-9]+)$ ]]; then
      echo "zse-ci: no PR number in session name '$name'"
      exec zsh
    fi
    pr=''${BASH_REMATCH[1]}
    interval=''${ZSE_CI_INTERVAL:-30}
    while :; do
      title=$(gh pr view "$pr" --json title,state --jq '.title + "  [" + .state + "]"' 2>&1)
      checks=$(gh pr checks "$pr" 2>&1)
      clear
      printf 'PR #%s  %s\n%s · every %ss · q quits\n\n%s\n' \
        "$pr" "$title" "$(date '+%H:%M:%S')" "$interval" "$checks"
      if read -rsn1 -t "$interval" key && [[ $key == q ]]; then
        exit 0
      fi
    done
  '';

  /**
    Right-hand column shared by `code`, `project.master` and `ticket`:
    shell on top, the `zse-git` pane below.
  */
  shellTigColumn = useCase: ''
    pane split_direction="horizontal" {
        ${mkShellPane useCase}
        pane name="git" {
            command "${zseGit}/bin/zse-git"
            args "${if useCase == null then "code" else useCase}"
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
    Wrap a pane tree in a single-pane-tree layout with the inline compact bar
    underneath. Used by `code`, `code-resume`, `ticket` and `review`.
    `project` uses `default_tab_template` instead and does not wrap here.
  */
  mkSingleTreeLayout = body: ''
    layout {
        pane split_direction="horizontal" {
            ${body}
            ${barPane}
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
    stable across pane restarts and `zse stop` / `zse restore`. If a transcript
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
  #   code     — default. claude (own conversation) · shell · tig status · compact bar.
  #   project  — tabs: master (code shape, --continue) + full-screen
  #              `claude agents`. Status via `default_tab_template`. Master
  #              shell shows a one-time `/project:start` welcome banner.
  #   ticket   — `claude --worktree $ZELLIJ_SESSION_NAME` · shell · tig.
  #              Session name is the ticket ID; worktree is created / reused
  #              at `.claude/worktrees/<id>`. Shell shows a one-time
  #              `/ticket:start` welcome banner.
  #   review   — `claude "/review:review $ZELLIJ_SESSION_NAME"` · shell ·
  #              CI pane (`zse-ci`, no tig). Session name is `review-<repo>-pr<n>`, parsed
  #              from a PR URL. The review command auto-fires in the claude
  #              pane; the shell shows a one-time banner noting that.
  #   daily    — claude --continue · tasks pane (`scripts/tasks-pane` from
  #              the daily-tasks repo: fzf over open tasks, tick in place).
  #
  # Welcome banners are a one-shot per session — a sentinel at
  # `~/.cache/zse/sessions/<name>.welcomed` suppresses the banner on resume.
  # `zse kill` deletes the sentinel so a reused session name re-welcomes.
  #
  # `code-resume` is a `--resume`-picker variant (`zse -l code-resume`).
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
      zseGit
      zseCi
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
        // No resurrection: an EXITED session would come back with its old
        // saved layout. The zse registry (~/.local/state/zse/sessions)
        // records the sessions; `zse restore` re-creates them from the
        // current layout files.
        session_serialization false
        keybinds {
            shared {
                bind "Ctrl Space" { LaunchOrFocusPlugin "session-manager" { floating true; }; SwitchToMode "Normal"; }
            }
        }
      '';

      # tig: periodic refresh, so the git pane follows Claude's edits and
      # commits without a manual `R`. Local `git status` only (no fetch).
      ".config/tig/config".text = ''
        set refresh-mode = periodic
        set refresh-interval = 5
      '';

      # ----- Use-case layouts -----

      ".config/zellij/layouts/code.kdl".text = mkSingleTreeLayout (threePaneBody null codeClaudePane);

      ".config/zellij/layouts/code-resume.kdl".text = mkSingleTreeLayout (
        threePaneBody null codeResumeClaudePane
      );

      ".config/zellij/layouts/ticket.kdl".text = mkSingleTreeLayout (
        threePaneBody "ticket" ticketClaudePane
      );

      # Review: claude + (shell over the CI pane). No tig — review is
      # read-first; the CI status is what a reviewer needs next to the diff.
      ".config/zellij/layouts/review.kdl".text = mkSingleTreeLayout ''
        pane split_direction="vertical" {
            ${reviewClaudePane}
            pane split_direction="horizontal" {
                ${mkShellPane "review"}
                pane name="ci" {
                    command "${zseCi}/bin/zse-ci"
                }
            }
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

      # Project uses `default_tab_template` so the compact bar renders in both
      # tabs. `focus=true` on master makes it the default on session open.
      ".config/zellij/layouts/project.kdl".text = ''
        layout {
            default_tab_template {
                children
                ${barPane}
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

  # The zse CLI (zse / zse ls|stop|kill|restore|switch, deprecated zsek /
  # zss / zsep, completion) lives in ./zse.zsh — plain zsh, no Nix escaping.
  programs.zsh.initContent = ''
    source ${./zse.zsh}
  '';
}
