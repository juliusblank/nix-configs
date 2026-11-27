{ pkgs, lib, ... }:

let
  /**
    Short repo names for zse session names (`rev-<short>-<n>-…`). Repos
    without an entry get a rule in `_z_repo_short` (zse.zsh): drop
    `taktile-`, initials for 3+ parts, else the first 8 chars.
  */
  zseRepoShort = {
    "workspace-services" = "ws";
    "taktile-infra" = "infra";
    "claude_code_fleet" = "fleet";
    "nix-configs" = "nix";
  };

  /**
    What zse.zsh needs: the repo short names, the shade colours, Claude's
    colours and the tool paths, then zse.zsh itself. One file, so that the
    subshells of `zse pick` (fzf preview, reload, the review requests) get
    the same: they source `$ZSE_SOURCE`.
  */
  zseSource = pkgs.writeText "zse-source.zsh" ''
    typeset -gA ZSE_REPO_SHORT=(${
      lib.concatStringsSep " " (
        lib.mapAttrsToList (k: v: "${lib.escapeShellArg k} ${lib.escapeShellArg v}") zseRepoShort
      )
    })
    typeset -gA ZSE_SHADE_RGB=(${
      lib.concatMapStringsSep " " (
        sh: "${sh.type}-${toString sh.n} '${lib.concatMapStringsSep ";" toString sh.rgb}'"
      ) zseShadeList
    })
    typeset -gA ZSE_CLAUDE_COLOR=(${
      lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "${k} ${v}") zseClaudeColor)
    })
    typeset -gx ZSE_TIMEOUT=${pkgs.coreutils}/bin/timeout
    typeset -gx ZSE_JQ=${pkgs.jq}/bin/jq
    source ${./zse.zsh}
  '';

  /**
    Loads zse: exports `ZSE_SOURCE` (see `zseSource`) and sources it. Used by
    ~/.zshrc and by `zse-pick`.
  */
  zsePrelude = ''
    typeset -gx ZSE_SOURCE=${zseSource}
    source ${zseSource}
  '';

  /**
    `zse-pick` — the zse session picker (`zse pick`) as a command, for the
    `Ctrl Space` binding: a floating pane that closes after the pick.
  */
  zsePick = pkgs.writeScriptBin "zse-pick" ''
    #!${pkgs.zsh}/bin/zsh -f
    ${zsePrelude}
    _zse_pick "$@"
  '';

  # ----- Colours (roadmap #42 phase 3) -----

  /**
    Four shades per type (base, lighter, darker, lightest) as RGB. The
    Zellij theme `zse-<type>-<n>` and the picker use them; `code-resume`
    uses `code`.
  */
  zseShades = {
    ticket = [
      [
        255
        194
        75
      ]
      [
        255
        215
        128
      ]
      [
        214
        158
        46
      ]
      [
        255
        235
        180
      ]
    ];
    project = [
      [
        255
        140
        50
      ]
      [
        255
        172
        105
      ]
      [
        214
        110
        30
      ]
      [
        255
        202
        155
      ]
    ];
    review = [
      [
        171
        224
        71
      ]
      [
        200
        240
        120
      ]
      [
        130
        185
        40
      ]
      [
        222
        250
        170
      ]
    ];
    review-doc = [
      [
        53
        187
        176
      ]
      [
        100
        215
        205
      ]
      [
        30
        150
        140
      ]
      [
        150
        235
        225
      ]
    ];
    explore = [
      [
        180
        130
        255
      ]
      [
        205
        170
        255
      ]
      [
        145
        95
        225
      ]
      [
        225
        200
        255
      ]
    ];
    code = [
      [
        81
        165
        250
      ]
      [
        130
        190
        255
      ]
      [
        50
        130
        215
      ]
      [
        175
        215
        255
      ]
    ];
    daily = [
      [
        170
        170
        170
      ]
      [
        200
        200
        200
      ]
      [
        140
        140
        140
      ]
      [
        225
        225
        225
      ]
    ];
  };

  /**
    Claude Code `/color` per use case (eight colours, no shades); daily
    keeps the default. `zse-claude` sends it on a new conversation.
  */
  zseClaudeColor = {
    ticket = "yellow";
    project = "orange";
    review = "green";
    review-doc = "cyan";
    explore = "purple";
    code = "blue";
  };

  /**
    All `{ type, n, rgb }` shades, n from 1.
  */
  zseShadeList = lib.concatLists (
    lib.mapAttrsToList (
      type: shades:
      lib.imap1 (n: rgb: {
        inherit type n rgb;
      }) shades
    ) zseShades
  );

  /**
    The Zellij theme `name`, matched to the Ghostty "0x96f" theme, with the
    accent `a` (`[ r g b ]`) on the selected tab, table titles and the
    focused pane frame. Component format (Zellij 0.42+), not the legacy
    palette: the legacy mapping draws the selected row of lists and tables
    (session manager, plugin lists) as #434343 on #262427, which is hard to
    see. Selected rows are dark text on 0x96f blue instead.
  */
  mkZellijTheme =
    name: accent:
    let
      a = lib.concatMapStringsSep " " toString accent;
    in
    ''
      themes {
          ${name} {
              text_unselected {
                  base 255 255 255
                  background 38 36 39
                  emphasis_0 255 194 75
                  emphasis_1 53 187 176
                  emphasis_2 171 224 71
                  emphasis_3 255 117 181
              }
              text_selected {
                  base 255 255 255
                  background 67 67 67
                  emphasis_0 255 194 75
                  emphasis_1 53 187 176
                  emphasis_2 171 224 71
                  emphasis_3 255 117 181
              }
              ribbon_selected {
                  base 38 36 39
                  background ${a}
                  emphasis_0 255 39 64
                  emphasis_1 255 194 75
                  emphasis_2 255 117 181
                  emphasis_3 81 165 250
              }
              ribbon_unselected {
                  base 38 36 39
                  background 255 255 255
                  emphasis_0 255 39 64
                  emphasis_1 255 255 255
                  emphasis_2 81 165 250
                  emphasis_3 255 117 181
              }
              table_title {
                  base ${a}
                  background 38 36 39
                  emphasis_0 255 194 75
                  emphasis_1 53 187 176
                  emphasis_2 171 224 71
                  emphasis_3 255 117 181
              }
              table_cell_selected {
                  base 38 36 39
                  background 81 165 250
                  emphasis_0 38 36 39
                  emphasis_1 38 36 39
                  emphasis_2 38 36 39
                  emphasis_3 38 36 39
              }
              table_cell_unselected {
                  base 255 255 255
                  background 38 36 39
                  emphasis_0 255 194 75
                  emphasis_1 53 187 176
                  emphasis_2 171 224 71
                  emphasis_3 255 117 181
              }
              list_selected {
                  base 38 36 39
                  background 81 165 250
                  emphasis_0 38 36 39
                  emphasis_1 38 36 39
                  emphasis_2 38 36 39
                  emphasis_3 38 36 39
              }
              list_unselected {
                  base 255 255 255
                  background 38 36 39
                  emphasis_0 255 194 75
                  emphasis_1 53 187 176
                  emphasis_2 171 224 71
                  emphasis_3 255 117 181
              }
              frame_selected {
                  base ${a}
                  background 38 36 39
                  emphasis_0 255 194 75
                  emphasis_1 53 187 176
                  emphasis_2 255 117 181
                  emphasis_3 38 36 39
              }
              frame_highlight {
                  base 255 194 75
                  background 38 36 39
                  emphasis_0 255 117 181
                  emphasis_1 255 194 75
                  emphasis_2 255 194 75
                  emphasis_3 255 194 75
              }
              exit_code_success {
                  base 171 224 71
                  background 38 36 39
                  emphasis_0 53 187 176
                  emphasis_1 67 67 67
                  emphasis_2 255 117 181
                  emphasis_3 81 165 250
              }
              exit_code_error {
                  base 255 39 64
                  background 38 36 39
                  emphasis_0 255 194 75
                  emphasis_1 38 36 39
                  emphasis_2 38 36 39
                  emphasis_3 38 36 39
              }
              multiplayer_user_colors {
                  player_1 255 117 181
                  player_2 81 165 250
                  player_3 53 187 176
                  player_4 255 194 75
                  player_5 171 224 71
                  player_6 255 39 64
                  player_7 255 194 75
                  player_8 255 255 255
                  player_9 81 165 250
                  player_10 53 187 176
              }
          }
      }
    '';

  /**
    config.kdl with the theme `theme`; `extra` is appended (a theme block).
    Flat KDL — same base as what `programs.zellij.settings` used to emit,
    plus a `shared` keybind that opens the zse picker (`zse pick`: fzf
    with activity, icons and PR news) in a floating pane in one keystroke
    (`Ctrl Space`). `Ctrl Space` is unused by zsh at the prompt and by
    every other Zellij default binding. Zellij's own session manager stays
    on `Ctrl o` → `w`.
  */
  mkZellijConfig = theme: extra: ''
    copy_command "pbcopy"
    default_shell "zsh"
    pane_frames false
    scroll_buffer_size 50000
    theme "${theme}"
    // No resurrection: an EXITED session would come back with its old
    // saved layout. The zse registry (~/.local/state/zse/sessions)
    // records the sessions; `zse restore` re-creates them from the
    // current layout files.
    session_serialization false
    keybinds {
        shared {
            bind "Ctrl Space" {
                Run "${zsePick}/bin/zse-pick" {
                    floating true
                    close_on_exit true
                    name "zse pick"
                }
                SwitchToMode "Normal"
            }
        }
    }
    ${extra}
  '';

  /**
    One config per shade, theme inline: `zse` starts a session with
    `zellij --config ~/.config/zellij/zse/<type>-<n>.kdl`, because Zellij
    0.45.1 ignores `options --theme` at creation.
  */
  zseShadeConfigs = lib.listToAttrs (
    map (
      sh:
      let
        theme = "zse-${sh.type}-${toString sh.n}";
      in
      lib.nameValuePair ".config/zellij/zse/${sh.type}-${toString sh.n}.kdl" {
        text = mkZellijConfig theme (mkZellijTheme theme sh.rgb);
      }
    ) zseShadeList
  );

  # ----- Session metadata -----

  /**
    `zse-meta KEY` — one name key of the current Zellij session from the zse
    registry (`~/.local/state/zse/sessions/<name>`, written by `zse`):
    `ticket`, `pr`, `owner`, `repo`, `slug`, `wt`, `title`, `hint`, `url`,
    `conv`. Sessions from before the name schema have no keys; for them the
    key comes from the session name as before: `wt` is `pr-<n>` for
    `review-<repo>-pr<n>`, else the name; `pr` the `-pr<n>` number; `ticket`
    / `slug` / `url` the name. `conv` has no fallback (zse-claude derives it).
  */
  zseMeta = pkgs.writeShellScriptBin "zse-meta" ''
    set -uo pipefail
    key=''${1:?usage: zse-meta KEY}
    name=''${ZELLIJ_SESSION_NAME:?zse-meta: run inside a Zellij session}
    f="''${XDG_STATE_HOME:-$HOME/.local/state}/zse/sessions/$name"
    val=$(sed -n "s/^$key=//p" "$f" 2>/dev/null | head -n 1)
    if [[ -z $val && -z $(sed -n 's/^names=//p' "$f" 2>/dev/null) ]]; then
      case $key in
        wt)
          if [[ $name =~ ^review-.+-pr([0-9]+)$ ]]; then val=pr-''${BASH_REMATCH[1]}; else val=$name; fi
          ;;
        pr) [[ $name =~ -pr([0-9]+)$ ]] && val=''${BASH_REMATCH[1]} ;;
        ticket | slug | url) val=$name ;;
      esac
    fi
    printf '%s\n' "$val"
  '';

  # ----- Welcome banner script -----

  /**
    Prints a one-time welcome in a `ticket` / `project` / `review` / `review-doc` / `explore`
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

    # Rename the current Zellij tab to a human-friendly label from the
    # session's name keys (`zse-meta`), with the use case's icon (the same as
    # `zse pick`): `◆ PCS-123 cache-ttl`, `✓ repo PR #<n> hint`. Run on every pane start — Zellij ignores
    # a rename-tab call whose target already matches, so this is cheap and
    # idempotent.
    meta=${zseMeta}/bin/zse-meta
    hint=$($meta hint)
    case "$use_case" in
      review)
        repo=$($meta repo)
        pr=$($meta pr)
        if [ -z "$repo" ]; then
          repo=''${name#review-}
          repo=''${repo%-pr*}
        fi
        label="✓ $repo PR #$pr''${hint:+ $hint}"
        ;;
      ticket) label="◆ $($meta ticket)''${hint:+ $hint}" ;;
      project) label="▲ $($meta slug)" ;;
      explore) label="✦ $($meta slug)" ;;
      review-doc) label="¶ ''${name#*doc-}" ;;
      *) label="" ;;
    esac
    # By tab ID, found from this pane's ID: `rename-tab` renames the focused tab
    # of a client, and a session created in the background (`zse restore`,
    # `zse migrate`, a start from inside Zellij) has no client yet, so it did
    # nothing there.
    if [ -n "$label" ]; then
      tab=$(zellij action list-panes --tab --json 2>/dev/null \
        | ${pkgs.jq}/bin/jq -r --arg id "''${ZELLIJ_PANE_ID:-}" \
          '.[] | select((.is_plugin | not) and ((.id | tostring) == $id)) | .tab_id' \
        | head -n 1)
      if [ -n "$tab" ]; then
        zellij action rename-tab-by-id "$tab" "$label" 2>/dev/null || true
      else
        zellij action rename-tab "$label" 2>/dev/null || true
      fi
    fi

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
        printf '→ /tktl-eng-delivery:ticket-start %s — prime ticket context (tktl-eng-delivery)\n' "$($meta ticket)"
        ;;
      project)
        cat <<'ART'
    ┏━━━━━━━━━━━┓
    ┃  PROJECT  ┃
    ┗━━━━━━━━━━━┛
    ART
        printf '→ /tktl-eng-delivery:project-start %s — bootstrap master session (tktl-eng-delivery)\n' "$($meta slug)"
        ;;
      review)
        cat <<'ART'
    ┏━━━━━━━━━━━┓
    ┃  REVIEW   ┃
    ┗━━━━━━━━━━━┛
    ART
        printf '→ /tktl-eng-delivery:review %s is auto-sent in the claude pane (tktl-eng-delivery)\n' "$($meta url)"
        ;;
      explore)
        cat <<'ART'
    ┏━━━━━━━━━━━┓
    ┃  EXPLORE  ┃
    ┗━━━━━━━━━━━┛
    ART
        printf '→ /explore status %s is auto-sent in the claude pane (repo skill)\n' "$($meta slug)"
        ;;
      review-doc)
        cat <<'ART'
    ┏━━━━━━━━━━━━━━┓
    ┃  REVIEW DOC  ┃
    ┗━━━━━━━━━━━━━━┛
    ART
        printf '→ /tktl-eng-delivery:review-doc <url> is auto-sent in the claude pane; you write each comment (tktl-eng-delivery)\n'
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
    `zse-shell USE_CASE` — the shell pane of the ticket / project / review /
    review-doc / explore layouts. Shows the one-time welcome, then moves into
    the session's worktree before it execs zsh: every pane starts in the
    session's start directory (the main checkout), and a KDL `cwd` cannot
    read the registry, so the pane does the `cd` itself.
    - ticket / explore: `.claude/worktrees/<wt>` (zse pre-creates it; waits
      up to 30 s for `claude --worktree` when it does not);
    - review: `.claude/worktrees/pr-<n>`, which `/tktl-eng-delivery:review`
      creates after the start (waits up to 180 s; Enter skips).
    Self-check: `git rev-parse --show-toplevel` must be the worktree. If not,
    a red warning names the directory and branch the shell is really in.
  */
  zseShell = pkgs.writeShellScriptBin "zse-shell" ''
    set -uo pipefail
    use_case=''${1:-}
    ${zseWelcome}/bin/zse-welcome "$use_case" || true
    wt_name="" wait_s=0
    case $use_case in
      ticket | explore) wt_name=$(${zseMeta}/bin/zse-meta wt) wait_s=30 ;;
      review) wt_name=$(${zseMeta}/bin/zse-meta wt) wait_s=180 ;;
    esac
    if [[ -n $wt_name ]] && root=$(git rev-parse --show-toplevel 2>/dev/null); then
      wt="$root/.claude/worktrees/$wt_name"
      # Ready = a git worktree whose top level is $wt. The directory alone is
      # not enough: `git worktree add` creates it before its `.git` file, and
      # a failed (e.g. sandboxed) attempt can leave it empty while Claude
      # retries.
      wt_ready() {
        [[ -e $wt/.git ]] &&
          [[ $(git -C "$wt" rev-parse --show-toplevel 2>/dev/null) == "$(cd "$wt" 2>/dev/null && pwd -P)" ]]
      }
      if ! wt_ready; then
        echo "zse-shell: waiting for $wt (up to ''${wait_s}s, Enter skips) …"
        for ((i = 0; i < wait_s; i++)); do
          wt_ready && break
          read -rs -t 1 && break
        done
      fi
      if [[ -d $wt ]] && cd "$wt" && [[ $(git rev-parse --show-toplevel 2>/dev/null) == "$(cd "$wt" && pwd -P)" ]]; then
        branch=$(git branch --show-current 2>/dev/null)
        [[ -n $branch ]] || branch="detached $(git rev-parse --short HEAD 2>/dev/null)"
        echo "zse-shell: ✓ in worktree $wt ($branch)"
      else
        printf '\033[1;31m%s\n%s\033[0m\n' \
          "zse-shell: ✗ NOT in the worktree $wt." \
          "This shell is in $PWD on branch $(git branch --show-current 2>/dev/null). Edits here do not reach the session's worktree."
      fi
    fi
    exec zsh
  '';

  /**
    Shell pane. When `useCase` is non-null (ticket / project / review /
    review-doc / explore), the pane runs `zse-shell <useCase>`: one-time
    welcome banner, `cd` into the session's worktree, then zsh. For `code` /
    `code-resume` the pane is plain zsh — no welcome, no indirection.
  */
  mkShellPane =
    useCase:
    if useCase == null then
      ''pane name="shell"''
    else
      ''
        pane name="shell" {
            command "${zseShell}/bin/zse-shell"
            args "${useCase}"
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
    for the session's worktree at `.claude/worktrees/<wt>` (`zse-meta wt`,
    the ticket ID), then shows only
    the ticket's commits: `tig <origin default branch>..HEAD` (origin, so a
    stale local `main` does not skew it). Every other use case shows
    `tig status` at the pane's directory. Refresh comes from tig's periodic
    mode (`~/.config/tig/config` below) — local `git status` only, never a
    fetch, so no SSH-agent / 1Password prompts.
  */
  zseGit = pkgs.writeShellScriptBin "zse-git" ''
    set -uo pipefail
    if [[ ''${1:-} == ticket ]]; then
      name=$(${zseMeta}/bin/zse-meta wt)
      root=$(git rev-parse --show-toplevel 2>/dev/null) || exec tig status
      wt="$root/.claude/worktrees/$name"
      for _ in $(seq 1 30); do
        [[ -d $wt ]] && break
        sleep 1
      done
      if [[ ! -d $wt ]]; then
        printf '\033[1;31m%s\033[0m\n' "zse-git: ✗ $wt not found after 30 s; showing the MAIN checkout's status instead"
        sleep 3
        exec tig status
      fi
      cd "$wt" || exit 1
      base=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
      exec tig "$base..HEAD"
    fi
    exec tig status
  '';

  /**
    `zse-ci` — the review status pane of the `review` layout (roadmap #44):
    PR state, review decision, mergeable, CI, and what is new since my last
    review or comment, from `gh` only (HTTPS, no SSH, no Claude) every
    `$ZSE_CI_INTERVAL` seconds (default 30). New items are highlighted; the
    review state (new, submitted, approved, closed, merged) goes to
    `~/.cache/zse/activity/<session>.pr` for the zse picker and `zse ls`,
    and as a marker (✱ ↩ ✔ ✗ ⇥) at the end of the tab name. Keys: `r` refresh, `t` Linear ticket status
    (`claude -p`, Haiku, on demand), `q` quit (Enter restarts the pane).
    Logic in ./zse-ci.sh and ./zse-ci.jq.
  */
  zseCi = pkgs.writeShellScriptBin "zse-ci" ''
    export ZSE_META=${zseMeta}/bin/zse-meta ZSE_CI_JQ=${./zse-ci.jq} \
      JQ=${pkgs.jq}/bin/jq TIMEOUT=${pkgs.coreutils}/bin/timeout
    exec ${pkgs.bash}/bin/bash ${./zse-ci.sh} "$@"
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
    name=$(${zseMeta}/bin/zse-meta slug)
    wt=$(${zseMeta}/bin/zse-meta wt)
    interval=''${ZSE_EXPLORE_INTERVAL:-10}
    while :; do
      file=""
      for root in "$PWD/.claude/worktrees/$wt" "$PWD"; do
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

    `--own` gives the Zellij session its own conversation. The ID is the
    registry's `conv` (set by `zse migrate`), else a UUID derived from the
    session name and the pane's start directory, so it is
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

    Colour (#42 phase 3): a new conversation starts with `/color <c>`
    (zseClaudeColor by `ZSE_USE_CASE`) as its first prompt; the transcript
    keeps it, so a resume restores it. With `--first-prompt TEXT` as well, a
    background job waits until the pane shows "Session color set to" and
    then types TEXT and Enter (`zellij action write-chars` / `send-keys`);
    it types nothing if the line does not appear within 10 min (e.g. the
    folder-trust dialog is still open). The pane ID goes to
    `~/.cache/zse/sessions/<name>.claude-pane` for `zse color`.
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
    case ''${ZSE_USE_CASE:-} in
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "  ${k}) color=${v} ;;") zseClaudeColor)}
      *) color="" ;;
    esac
    if [[ -n ''${ZELLIJ_PANE_ID:-} ]]; then
      cache="''${XDG_CACHE_HOME:-$HOME/.cache}/zse/sessions"
      mkdir -p "$cache"
      printf '%s\n' "$ZELLIJ_PANE_ID" >"$cache/$name.claude-pane"
    fi
    if [[ ''${1:-} == --first-prompt ]]; then
      first=("''${2:?zse-claude: --first-prompt needs a text}")
      shift 2
    fi

    # Keep in sync with `_z_conv_id` in zse.zsh. `zse migrate` stores the
    # old name's ID as `conv`, so a renamed session resumes its conversation.
    id=$(${zseMeta}/bin/zse-meta conv)
    if [[ -z $id ]]; then
      h=$(printf 'zse:%s:%s' "$name" "$PWD" | shasum -a 256 | cut -c1-32)
      id="''${h:0:8}-''${h:8:4}-5''${h:13:3}-8''${h:17:3}-''${h:20:12}"
    fi

    shopt -s nullglob
    transcripts=("''${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$id".jsonl)
    if ((''${#transcripts[@]})); then
      exec claude "''${base[@]}" --resume "$id" "$@"
    fi
    if [[ -n $color ]]; then
      if ((''${#first[@]})) && [[ -n ''${ZELLIJ_PANE_ID:-} ]]; then
        (
          pane=$ZELLIJ_PANE_ID
          for _ in $(seq 1200); do
            sleep 0.5
            if zellij action dump-screen --pane-id "$pane" 2>/dev/null | grep -q 'Session color set to'; then
              sleep 0.5
              zellij action write-chars --pane-id "$pane" "''${first[0]}"
              sleep 0.3
              zellij action send-keys --pane-id "$pane" Enter
              exit 0
            fi
          done
        ) </dev/null >/dev/null 2>&1 &
      fi
      first=("/color $color")
    fi
    exec claude "''${base[@]}" --session-id "$id" "$@" "''${first[@]}"
  '';

  /**
    Interactive claude pane for a use case. It exports `ZSE_USE_CASE=<useCase>`
    for zse's own scripts and, for the use cases the delivery plugins know
    (`project`, `ticket`, `review`, `review-doc`), `DELIVERY_SESSION=<useCase>`:
    the plugins' SessionStart hooks key off it (the `project` hook injects the
    master-session ground rules). It runs `zse-claude` with
    `args` (already KDL-string-escaped). One shell wraps the exec so
    `$ZELLIJ_SESSION_NAME`, which Zellij sets per pane at session creation,
    interpolates at pane start — ticket / review sessions share one layout
    file and each sees its own name.
  */
  mkClaudePane =
    useCase: args:
    let
      delivery =
        if
          builtins.elem useCase [
            "project"
            "ticket"
            "review"
            "review-doc"
          ]
        then
          " DELIVERY_SESSION=${useCase}"
        else
          "";
    in
    ''
      pane name="claude" {
          command "sh"
          args "-c" "export ZSE_USE_CASE=${useCase}${delivery}; exec ${zseEnv}/bin/zse-env ${zseClaude}/bin/zse-claude ${args}"
      }
    '';

  codeClaudePane = mkClaudePane "code" "--own";
  codeResumeClaudePane = mkClaudePane "code" "--resume";
  projectClaudePane = mkClaudePane "project" "--own";
  dailyClaudePane = mkClaudePane "daily" "--own";
  # Ticket: the worktree is the ticket ID (`zse-meta wt`), not the session name.
  ticketClaudePane = mkClaudePane "ticket" ''--own --worktree \"$(${zseMeta}/bin/zse-meta wt)\"'';
  # Explicit namespace (`/tktl-eng-delivery:review`) over the shorthand (`/review`) so
  # the command stays unambiguous: other plugins have their own `review`.
  # `--first-prompt`: the review runs on the first start only; a restored
  # session resumes its conversation.
  # The PR URL from the registry (`zse-meta url`; old-style sessions: the
  # `review-<repo>-pr<n>` name, which the command also accepts).
  reviewClaudePane = mkClaudePane "review" ''--own --first-prompt \"/tktl-eng-delivery:review $(${zseMeta}/bin/zse-meta url)\"'';
  # Review-doc: `/tktl-eng-delivery:review-doc <url>` on the first start, URL from the registry.
  reviewDocClaudePane = mkClaudePane "review-doc" ''--own --first-prompt \"/tktl-eng-delivery:review-doc $(${zseMeta}/bin/zse-meta url)\"'';
  # Explore: own conversation in the slug's worktree; `/explore status` on the
  # first start only, so every new session opens with goal, iteration and budget.
  exploreClaudePane = mkClaudePane "explore" ''--own --first-prompt \"/explore status $(${zseMeta}/bin/zse-meta slug)\" --worktree \"$(${zseMeta}/bin/zse-meta wt)\"'';

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
  #              `/tktl-eng-delivery:project-start` welcome banner.
  #   ticket   — `claude --worktree <ID>` · shell · tig. Session name
  #              `tkt-<ID>-<hint>`; worktree `.claude/worktrees/<ID>` from
  #              the delivery plugin's `worktree.sh` (zse's own fallback).
  #              Shell shows a one-time `/tktl-eng-delivery:ticket-start` banner.
  #   review   — `zse-claude --own --first-prompt "/tktl-eng-delivery:review <PR URL>"` ·
  #              shell · CI pane (`zse-ci`, no tig). Session name
  #              `rev-<repo>-<n>-<hint>` from a PR URL. The review command
  #              auto-fires on the first start only; a restored session
  #              resumes. The shell shows a one-time banner.
  #   review-doc — `zse-claude --own --first-prompt "/tktl-eng-delivery:review-doc <url>"` ·
  #              shell (no tig, no CI). Session name `doc-<title>-<id8>` from a
  #              Notion URL, or `doc-<repo>-<n>` from a PR URL. The command
  #              interviews the user for each comment (tktl-eng-delivery).
  #   daily    — claude (own conversation) · tasks pane (`scripts/tasks-pane` from
  #              the daily-tasks repo: fzf over open tasks, tick in place).
  #   explore  — private explorations (docs/SPEC.md → Explorations). Session
  #              name `exp-<slug>`; worktree `.claude/worktrees/<slug>` on
  #              branch `explore/<slug>`. claude (`/explore status <slug>` on
  #              the first start) · shell · exploration pane (`zse-explore`).
  #
  # Name keys (ticket, PR, slug, worktree, URL, …) live in the zse registry;
  # panes read them with `zse-meta` (old-style names: parsed from the name).
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
      zseEnv
      zseMeta
      zseShell
      zsePick
    ];

    file = {
      # ----- Config -----

      # The default config (sessions without a shade); see mkZellijConfig.
      ".config/zellij/config.kdl".text = mkZellijConfig "ghostty-0x96f" "";

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

      # Review-doc: claude + shell. No tig, no CI — the doc is in Notion or in
      # the PR; the interview happens in the claude pane.
      ".config/zellij/layouts/review-doc.kdl".text = mkSingleTreeLayout ''
        pane split_direction="vertical" {
            ${reviewDocClaudePane}
            ${mkShellPane "review-doc"}
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

      # Zellij theme matched to the Ghostty "0x96f" theme (see home/ghostty.nix
      # and mkZellijTheme), as a theme file so config.kdl just names it.
      ".config/zellij/themes/ghostty-0x96f.kdl".text = mkZellijTheme "ghostty-0x96f" [
        171
        224
        71
      ];
    }
    // zseShadeConfigs;
  };

  # The zse CLI (zse / zse ls|stop|kill|restore|switch, deprecated zsek /
  # zss / zsep, completion) lives in ./zse.zsh — plain zsh, no Nix escaping.
  # zsePrelude sets `ZSE_REPO_SHORT` (zseRepoShort) and the tool paths
  # before it.
  programs.zsh.initContent = zsePrelude;
}
