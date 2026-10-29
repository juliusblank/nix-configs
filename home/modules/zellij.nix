{ pkgs, ... }:

let
  # ----- Welcome banner script -----

  /**
    Prints a one-time welcome in a `ticket` / `project` / `review` / `explore`
    shell pane.
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
      explore)
        zellij action rename-tab "[explore] $name" 2>/dev/null || true
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
      explore)
        cat <<'ART'
    ┏━━━━━━━━━━━┓
    ┃  EXPLORE  ┃
    ┗━━━━━━━━━━━┛
    ART
        printf '→ /explore status %s is auto-sent in the claude pane (repo skill)\n' "$name"
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
    `zse-env CMD [ARGS…]` — run CMD with the devshell of the current
    directory (the repo's `.envrc`, through nix-direnv), then exec it. Every
    command pane in the layouts starts through it: command panes do not run
    the zsh direnv hook, and the Zellij server env (from whoever ran `zse`)
    must not decide which devshell a pane gets. No `.envrc`, or a blocked
    one: CMD runs with the env it has.
  */
  zseEnv = pkgs.writeShellScriptBin "zse-env" ''
    eval "$(${pkgs.direnv}/bin/direnv export bash 2>/dev/null)"
    exec "$@"
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
    `zse-explore` — the exploration pane of the `explore` layout. Shows
    `docs/explorations/<name>.md` of the session's worktree
    (`.claude/worktrees/<name>`, falling back to the repo root), rendered by
    `bat` and cut to the pane height so the header, brief and goal stay in
    view. Redraws every `$ZSE_EXPLORE_INTERVAL` seconds (default 10), so
    Claude's edits show up. `q` quits; the command pane then waits for Enter.
  */
  zseExplore = pkgs.writeShellScriptBin "zse-explore" ''
    set -uo pipefail
    name=''${ZELLIJ_SESSION_NAME:-}
    interval=''${ZSE_EXPLORE_INTERVAL:-10}
    while :; do
      file=""
      for root in "$PWD/.claude/worktrees/$name" "$PWD"; do
        if [[ -f $root/docs/explorations/$name.md ]]; then
          file=$root/docs/explorations/$name.md
          break
        fi
      done
      clear
      rows=$(( $(tput lines 2>/dev/null || echo 40) - 2 ))
      if [[ -n $file ]]; then
        printf '%s · every %ss · q quits\n' "$(date '+%H:%M:%S')" "$interval"
        ${pkgs.bat}/bin/bat --style=plain --color=always --paging=never --language=markdown \
          --terminal-width="$(tput cols 2>/dev/null || echo 80)" "$file" | head -n "$rows"
      else
        printf 'zse-explore: no docs/explorations/%s.md yet — run /explore new in the claude pane.\n' "$name"
      fi
      if read -rsn1 -t "$interval" key && [[ $key == q ]]; then
        exit 0
      fi
    done
  '';

  /**
    `zse-blog prompt|view|render|edit|draft` — helper of the `blog` layout
    (roadmap #37). The session is `blog-<ticket | slug>`; its worktree is
    `.claude/worktrees/<session>` under the pane's directory (the
    engineering-blog checkout). The draft is the newest `drafts/*.md` that is
    new or changed against origin's default branch, so Claude picks the slug.

      prompt   first message of the claude pane: ticket or topic, then the
               `tktl-eng:tktl-eng-blog-voice` workflow and the repo's format rules
      view     draft view: `watchexec` runs `render` on every save in drafts/
      render   `glow` of the draft, then a status line: words, reading time,
               Vale hits (TaktileBlog, home/modules/prose.nix) and whether
               `scripts/md-to-sanity.py` converts the draft
      edit     waits for the draft, then opens it in Neovim with ZenMode
      draft    prints the draft path (empty if there is none yet)
  */
  zseBlog = pkgs.writeShellScriptBin "zse-blog" ''
    set -uo pipefail
    name=''${ZELLIJ_SESSION_NAME:?zse-blog: run inside a Zellij session}
    topic=''${name#blog-}
    root=''${ZSE_BLOG_ROOT:-$PWD}
    wt=$root/.claude/worktrees/$name
    vale_config=$HOME/.config/vale/taktile-blog/.vale.ini

    draft() {
      cd "$wt" 2>/dev/null || return 0
      local base f
      base=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
      { git diff --name-only "$base" -- 'drafts/*.md' 2>/dev/null
        git ls-files --others --exclude-standard -- 'drafts/*.md'
      } | sort -u | while read -r f; do
        [[ -f $f ]] && printf '%s %s\n' "$(${pkgs.coreutils}/bin/stat -c %Y "$f")" "$wt/$f"
      done | sort -rn | head -n 1 | cut -d' ' -f2-
    }

    prompt() {
      local start
      if [[ $topic =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]; then
        start="Read the Linear ticket $topic: topic, audience, material and constraints. Its description may hold a post brief from an earlier session."
      else
        start="There is no ticket. Ask me for the topic, the audience and the one point the post makes, or for a post brief from an earlier session."
      fi
      cat <<EOF
    Blog session $name: one Engineering blog post, written in this worktree (branch blog/$topic).
    1. $start
    2. Read AGENTS.md and the header of scripts/md-to-sanity.py. The draft may use only what the converter supports: paragraphs, "## " headings, images as ![alt](/blog/<slug>/<file>), inline code and <a href="..."> links. No lists, tables, emphasis, code blocks or Markdown links.
    3. Use the skill tktl-eng:tktl-eng-blog-voice (not blog-writer): choose the register and the archetype, propose an outline, and wait for my OK.
    4. Write the draft to drafts/<slug>.md (<slug>: short kebab-case, it becomes the URL), with frontmatter title, description, pubDate ('Mon DD YYYY'), heroImage, tags: ['Engineering'], authors. Then review it with the skill's checklist.
    The draft view next to you shows the Vale (TaktileBlog) hits and whether md-to-sanity converts the file: fix both. I also edit the file in the "edit" tab, so read the file again before every change.
    When I say the draft is ready: commit, push and open a PR in engineering-blog. With a ticket, add the PR link as a comment on it. Do not publish to Sanity.
    EOF
    }

    render() {
      local f words hits vale sanity assets out cols
      f=$(draft)
      if [[ -z $f ]]; then
        echo "No draft yet. Claude writes it to drafts/<slug>.md."
        return 0
      fi
      cols=$(tput cols 2>/dev/null || echo 80)
      ${pkgs.glow}/bin/glow -s dark -w "$cols" "$f"
      words=$(awk 'NR == 1 && $0 != "---" { fm = 2 } fm < 2 && $0 == "---" { fm++; next } fm >= 2' "$f" | wc -w | tr -d ' ')
      # --no-exit: alerts exit 0, so a non-zero exit is a Vale runtime error.
      if hits=$(${pkgs.vale}/bin/vale --config="$vale_config" --output=line --no-exit "$f" 2>&1); then
        vale=$(printf '%s' "$hits" | grep -c .)
      else
        vale=error
      fi
      # md-to-sanity needs an asset id per image; any id does for this check.
      assets=$(mktemp)
      printf '{"hero": "x"%s}\n' "$(grep -oE '\]\(/blog/[^/]+/[^)]+\)' "$f" \
        | sed -E 's@.*/([^/)]+)\)$@, "\1": "x"@' | tr -d '\n')" > "$assets"
      if out=$(${pkgs.python3}/bin/python3 "$wt/scripts/md-to-sanity.py" "$f" "$assets" 2>&1 >/dev/null); then
        sanity=ok
      else
        sanity="FAILS: $(printf '%s' "$out" | head -n 2 | tr '\n' ' ')"
      fi
      rm -f "$assets"
      printf '\n%s\n' "$(printf '%*s' "$cols" "" | tr ' ' '-')"
      [[ -n $hits ]] && printf '%s\n' "$hits" | sed "s@^$wt/@@"
      printf '%s · %s words · ~%s min · vale: %s · md-to-sanity: %s · %s\n' \
        "''${f#"$wt"/}" "$words" "$(( (words + 199) / 200 ))" \
        "$vale" "$sanity" "$(date '+%H:%M:%S')"
    }

    case ''${1:-} in
      prompt) prompt ;;
      draft) draft ;;
      render) render ;;
      view)
        cd "$wt" 2>/dev/null || { echo "zse-blog: no worktree at $wt"; exec zsh; }
        export ZSE_BLOG_ROOT=$root
        exec ${pkgs.watchexec}/bin/watchexec --watch drafts --exts md --clear --quiet \
          --shell=none -- "$0" render
        ;;
      edit)
        until f=$(draft) && [[ -n $f ]]; do
          clear
          echo "Waiting for the draft in drafts/ (Claude writes it after the outline) ..."
          sleep 3
        done
        cd "$wt" || exit 1
        exec nvim -c ZenMode "$f"
        ;;
      *)
        echo "usage: zse-blog prompt|view|render|edit|draft" >&2
        exit 2
        ;;
    esac
  '';

  /**
    `zse-agents` — the agents pane of the `project` master tab. Redraws the
    Claude sessions started under the pane's directory (the repo root, so
    ticket worktrees at `.claude/worktrees/<id>` are included) every
    `$ZSE_AGENTS_INTERVAL` seconds (default 5): state, name, kind, age,
    worktree. Source is `claude agents --json --cwd`, the only stable
    interface for agent status; `state` / `waitingFor` are shown when the
    JSON has them, else `status`. The master's own session is left out.
    `q` quits; the command pane then waits for Enter to restart it.
  */
  zseAgents = pkgs.writeShellScriptBin "zse-agents" ''
    set -uo pipefail
    self=''${ZELLIJ_SESSION_NAME:-}
    dir=$PWD
    interval=''${ZSE_AGENTS_INTERVAL:-5}
    while :; do
      if json=$(claude agents --json --cwd "$dir" 2>&1); then
        body=$(printf '%s' "$json" | ${pkgs.jq}/bin/jq -r \
          --arg self "$self" --arg dir "$dir" --argjson now "$(date +%s)" '
            map(select(.name != $self or .cwd != $dir))
            | sort_by(.startedAt)
            | .[]
            | [ (.state // .status // "-"),
                .name,
                (if .kind == "background" then "bg" else "int" end),
                (($now - (.startedAt / 1000 | floor)) as $s
                  | if $s < 3600 then "\($s / 60 | floor)m"
                    elif $s < 86400 then "\($s / 3600 | floor)h"
                    else "\($s / 86400 | floor)d" end),
                ((.cwd | capture("/\\.claude/worktrees/(?<w>[^/]+)").w) // "-"),
                (.waitingFor // "")
              ]
            | @tsv' | column -t -s $'\t')
        [[ -n $body ]] || body="no other sessions under $dir"
      else
        body="zse-agents: claude agents --json failed: $json"
      fi
      clear
      printf 'agents · %s · every %ss · q quits\n\n%s\n' \
        "$(date '+%H:%M:%S')" "$interval" "$body"
      if read -rsn1 -t "$interval" key && [[ $key == q ]]; then
        exit 0
      fi
    done
  '';

  /**
    Right-hand column shared by `code`, `project.master` and `ticket`:
    shell on top, the `zse-git` pane below. In `project` the bottom row
    splits into git (left) and `zse-agents` (right).
  */
  shellTigColumn =
    useCase:
    let
      gitPane = ''
        pane name="git" {
            command "${zseEnv}/bin/zse-env"
            args "${zseGit}/bin/zse-git" "${if useCase == null then "code" else useCase}"
        }
      '';
      bottom =
        if useCase == "project" then
          ''
            pane split_direction="vertical" {
                ${gitPane}
                pane name="agents" {
                    command "${zseEnv}/bin/zse-env"
                    args "${zseAgents}/bin/zse-agents"
                }
            }
          ''
        else
          gitPane;
    in
    ''
      pane split_direction="horizontal" {
          ${mkShellPane useCase}
          ${bottom}
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
    `zse-claude [--own [--first-prompt TEXT]] [CLAUDE_ARGS…]` — the claude
    launcher for every interactive zse pane.

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

    `--first-prompt TEXT` (after `--own`) sends TEXT as the first user
    message only when the conversation is new. On resume it is dropped, so
    a stopped / restored `review` session does not run the review again.
  */
  zseClaude = pkgs.writeShellScriptBin "zse-claude" ''
    set -euo pipefail
    name=''${ZELLIJ_SESSION_NAME:?zse-claude: run inside a Zellij session}
    base=(--remote-control "$name" --name "$name")

    if [[ ''${1:-} != --own ]]; then
      exec claude "''${base[@]}" "$@"
    fi
    shift
    first=()
    if [[ ''${1:-} == --first-prompt ]]; then
      first=("''${2:?zse-claude: --first-prompt needs a text}")
      shift 2
    fi

    h=$(printf 'zse:%s:%s' "$name" "$PWD" | shasum -a 256 | cut -c1-32)
    id="''${h:0:8}-''${h:8:4}-5''${h:13:3}-8''${h:17:3}-''${h:20:12}"

    shopt -s nullglob
    transcripts=("''${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$id".jsonl)
    if ((''${#transcripts[@]})); then
      exec claude "''${base[@]}" --resume "$id" "$@"
    fi
    exec claude "''${base[@]}" --session-id "$id" "$@" "''${first[@]}"
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
        args "-c" "export ZSE_USE_CASE=${useCase}; exec ${zseEnv}/bin/zse-env ${zseClaude}/bin/zse-claude ${args}"
    }
  '';

  codeClaudePane = mkClaudePane "code" "--own";
  codeResumeClaudePane = mkClaudePane "code" "--resume";
  projectClaudePane = mkClaudePane "project" "--own";
  dailyClaudePane = mkClaudePane "daily" "--own";
  ticketClaudePane = mkClaudePane "ticket" ''--own --worktree \"$ZELLIJ_SESSION_NAME\"'';
  # Explicit namespace (`/review:review`) over the shorthand (`/review`) so
  # the command stays unambiguous as more plugins add their own `review`.
  # `--first-prompt`: the review runs on the first start only; a restored
  # session resumes its conversation.
  reviewClaudePane = mkClaudePane "review" ''--own --first-prompt \"/review:review $ZELLIJ_SESSION_NAME\"'';
  # Explore: own conversation in the slug's worktree; `/explore status` on the
  # first start only, so every new session opens with goal, iteration and budget.
  exploreClaudePane = mkClaudePane "explore" ''--own --first-prompt \"/explore status $ZELLIJ_SESSION_NAME\" --worktree \"$ZELLIJ_SESSION_NAME\"'';
  # Blog: own conversation in the post's worktree; the first start gets the
  # writing brief from `zse-blog prompt` (ticket or topic, blog-voice skill).
  blogClaudePane = mkClaudePane "blog" ''--own --first-prompt \"$(${zseBlog}/bin/zse-blog prompt)\" --worktree \"$ZELLIJ_SESSION_NAME\"'';

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
        args "-c" "[ -x scripts/tasks-pane ] && exec ${zseEnv}/bin/zse-env scripts/tasks-pane; echo 'zse daily: no executable scripts/tasks-pane in this repo'; exec zsh"
    }
  '';

in
{
  # Zellij terminal multiplexer — one session per project / Claude workflow.
  #
  # Use-case layouts (see docs/usage/zellij.md for the long form):
  #
  #   code     — default. claude (own conversation) · shell · tig status · compact bar.
  #   project  — tabs: master (code shape, own conversation; git row split
  #              with the `zse-agents` status pane) + full-screen
  #              `claude agents --cwd <repo>`. Status via
  #              `default_tab_template`. Master shell shows a one-time
  #              `/project:start` welcome banner.
  #   ticket   — `claude --worktree $ZELLIJ_SESSION_NAME` · shell · tig.
  #              Session name is the ticket ID; worktree is created / reused
  #              at `.claude/worktrees/<id>`. Shell shows a one-time
  #              `/ticket:start` welcome banner.
  #   review   — `zse-claude --own --first-prompt "/review:review $NAME"` ·
  #              shell · CI pane (`zse-ci`, no tig). Session name is
  #              `review-<repo>-pr<n>`, parsed from a PR URL. The review
  #              command auto-fires on the first start only; a restored
  #              session resumes. The shell shows a one-time banner.
  #   daily    — claude (own conversation) · tasks pane (`scripts/tasks-pane` from
  #              the daily-tasks repo: fzf over open tasks, tick in place).
  #   explore  — private explorations (docs/SPEC.md → Explorations). Session
  #              name is the slug; worktree `.claude/worktrees/<slug>` on
  #              branch `explore/<slug>`. claude (`/explore status <slug>` on
  #              the first start) · shell · exploration pane (`zse-explore`).
  #   blog     — Engineering blog posts (roadmap #37). Session `blog-<ticket | slug>`
  #              in the engineering-blog checkout; worktree `.claude/worktrees/<session>`
  #              on branch `blog/<ticket | slug>`. Tabs: write = claude (blog-voice
  #              brief on the first start) · draft view (`zse-blog view`) · shell;
  #              edit = Neovim on the draft (prose mode, home/modules/prose.nix).
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
    # Zellij >= 0.45 puts sockets in `$TMPDIR/zellij-<uid>/contract_version_1/`
    # (80 chars on macOS). The macOS socket path limit is 104, so session names
    # were capped at 24 chars (`review-workspace-services-pr20650` failed with
    # "must be less than 0 characters"). A short, private dir allows ~55.
    # Changing it hides running sessions from the new client: `zse stop` them
    # before the deploy, `zse restore` after.
    sessionVariables.ZELLIJ_SOCKET_DIR = "$HOME/.cache/zj";

    packages = [
      pkgs.tig
      zseWelcome
      zseClaude
      zseGit
      zseCi
      zseExplore
      zseAgents
      zseBlog
      zseEnv
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
                    command "${zseEnv}/bin/zse-env"
                    args "${zseCi}/bin/zse-ci"
                }
            }
        }
      '';

      # Explore: claude + (shell over the exploration file). No tig — the
      # exploration file is what matters next to the conversation.
      ".config/zellij/layouts/explore.kdl".text = mkSingleTreeLayout ''
        pane split_direction="vertical" {
            ${exploreClaudePane}
            pane split_direction="horizontal" {
                ${mkShellPane "explore"}
                pane name="exploration" size="65%" {
                    command "${zseExplore}/bin/zse-explore"
                }
            }
        }
      '';

      # Blog: tab "write" = claude + (draft view over a shell in the worktree);
      # tab "edit" = Neovim on the draft. No tig — the PR is the review.
      ".config/zellij/layouts/blog.kdl".text = ''
        layout {
            default_tab_template {
                children
                ${barPane}
            }
            tab name="write" focus=true {
                pane split_direction="vertical" {
                    ${blogClaudePane}
                    pane split_direction="horizontal" size="45%" {
                        pane name="draft" size="75%" {
                            command "${zseBlog}/bin/zse-blog"
                            args "view"
                        }
                        pane name="shell" {
                            command "sh"
                            args "-c" "cd \".claude/worktrees/$ZELLIJ_SESSION_NAME\" 2>/dev/null; exec zsh"
                        }
                    }
                }
            }
            tab name="edit" {
                pane name="editor" {
                    command "${zseBlog}/bin/zse-blog"
                    args "edit"
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
                    command "sh"
                    args "-c" "exec ${zseEnv}/bin/zse-env claude agents --cwd \"$PWD\""
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
