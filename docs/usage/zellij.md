# Zellij — Claude Code session terminal management

This is how the `nix-configs` repo organises Claude Code work in a single
Ghostty window. One Zellij session per Claude workflow, five use-case layouts
picked by use case.

## Use cases and layouts

Zellij session name = Claude workflow name = worktree name (project slug,
ticket ID, or `review-<repo>-pr<n>` from a PR URL). Ticket branches are
`$ZSE_BRANCH_USER/<id>`, not the bare session name.

| Use case | Layout file | Pane shape | Claude command |
|---|---|---|---|
| **code** (default) | `code.kdl` | claude · (shell · tig) · compact bar | `zse-claude --own` |
| **project** | `project.kdl` | tabs: master (claude · (shell · (git \| agents status))) + agents (full-screen) | master: `zse-claude --own`; agents: `claude agents --cwd <repo>` |
| **ticket** | `ticket.kdl` | claude · (shell · tig) · compact bar | `zse-claude --own --worktree $ZELLIJ_SESSION_NAME` |
| **review** | `review.kdl` | claude · (shell · CI) · compact bar (no tig) | `zse-claude --own --first-prompt "/review:review $ZELLIJ_SESSION_NAME"` (review on first start; own conversation) |
| **daily** | `daily.kdl` | claude · tasks (40 %) · compact bar | `zse-claude --own`; tasks pane runs `scripts/tasks-pane` |

Every interactive claude pane runs `zse-claude` (installed by the
module), which adds `--remote-control "$ZELLIJ_SESSION_NAME"` (the session
is addressable from the account's other Remote-Control-enrolled devices
under the same name the Zellij session has locally) and `--name
"$ZELLIJ_SESSION_NAME"` (prompt box, `/resume` picker, terminal title).

`zse-claude --own` gives each Zellij session **its own conversation**: the
conversation ID is a UUID derived from the session name and the pane's
start directory. If a transcript with that ID exists, the pane resumes it
(`--resume <id>`); otherwise it starts a fresh conversation under that ID
(`--session-id <id>`). This replaces `claude --continue`, which resumes
the most recent conversation **in the directory** — so a new `project`
master in a repo where a `code` session ran before picked up that
session's conversation. Old conversations stay reachable via `/resume`.

The `agents` tab in `project` runs `claude agents --cwd <repo>` — a
management view, not an interactive REPL.

Each claude pane also exports `ZSE_USE_CASE=<code|project|ticket|review|daily>`
(`code-resume` exports `code`). Plugins use it to tailor a session to its
layout: the `jbl-personal` `project` plugin has a `SessionStart` hook that
injects the master-session ground rules (`project/rules.md`: role,
phases, ADR change handling) when `ZSE_USE_CASE=project` and the cwd is
not a `.claude/worktrees/*` sub-session. The hook fires on startup,
resume, clear and compact, so the rules survive compaction. The rules
live in the plugin repo, so changing them needs no nix deploy.

Plus a `code-resume.kdl` variant that uses `claude --resume` (opens the
picker) instead of `--own` — start it with `zse -l code-resume`.

The source of truth is a Nix generator in `home/modules/zellij.nix`:
shared pane fragments (`barPane`, `shellTigColumn`, `threePaneBody`)
compose into the per-layout `.kdl` files on activation.

Every command pane (claude, git, CI, tasks, `claude agents`) starts through
`zse-env`, which loads the devshell of the pane's directory (`direnv export`,
nix-direnv) and then runs the command. Command panes do not run the zsh
direnv hook, and the Zellij server env does not decide which devshell a pane
gets. Shell panes run the hook as usual.

`ticket` and `review` reference `$ZELLIJ_SESSION_NAME`, an env var Zellij
sets per pane at session creation. Each ticket / review session sees its
own name without the layout files needing to be rendered per session.

## Welcome banners

The `ticket`, `project`, and `review` layouts show a one-time banner in
the shell pane on fresh session creation, printed by the `zse-welcome`
helper (installed via home-manager):

```
┏━━━━━━━━━━━┓
┃  TICKET   ┃
┗━━━━━━━━━━━┛
→ /ticket:start PCS-13558 — prime ticket context (jbl-personal/ticket)
```

A sentinel at `~/.cache/zse/sessions/<name>.welcomed` suppresses the
banner on resume. `zse kill` deletes the sentinel so a reused session name
re-welcomes. `code` and `code-resume` have no banner — those shell panes
are plain zsh.

For `review`, the claude pane auto-sends `/review:review $NAME` on
the first start (not on restore); the banner just reports what's running. For `ticket` and
`project`, the user invokes the kickoff command manually from the
banner's hint.

## Use-case specifics

### code

The default `zse` shape: claude resumes the session's own conversation, a
shell to run commands, and the git pane.

**Git pane (`zse-git`).** `tig status` at the repo root; in `ticket`
sessions it waits for `.claude/worktrees/<id>` and shows only the
ticket's commits (`tig origin/<default>..HEAD`). In tig: `Enter` opens a
commit's diff, `s` the status, `t` the file tree at that commit, `q` goes
back. tig refreshes every 5 s (`~/.config/tig/config`, `refresh-mode
periodic`) — local `git status` only, never a fetch, so no 1Password
SSH-agent prompts.

### project

A long-running "master" plan that dispatches ticket sub-sessions via
`claude agents`. Two explicit tabs:

- **master** (default focus): `zse-claude --own` from the repo root — the
  project's own conversation, independent of other sessions in the same
  repo and of agent sub-sessions.
  The git row on the right splits into git (left) and the **agents
  status pane (`zse-agents`)** (right): one line per Claude session under
  the repo root (state, name, `int` / `bg`, age, worktree), redrawn every
  5 s (`ZSE_AGENTS_INTERVAL`), master itself left out. Source is
  `claude agents --json --cwd <repo>` — Claude Code has no compact or
  embeddable agent view of its own. `q` quits; Enter restarts it.
- **agents**: full-screen `claude agents --cwd <repo>` for inspecting,
  attaching to, and dispatching sessions. `--cwd` keeps the list to
  sessions started under the repo root (including `.claude/worktrees/*`);
  other sessions in the same repo (e.g. a `code` session) also show.

The compact bar renders in both tabs via `default_tab_template` and shows
`master | agents` with the active tab highlighted. Switch tabs with
`Alt ←` / `Alt →`, or `Ctrl t` then `←` / `→` or `1`–`9`.

### ticket

A single standalone ticket (bug fix, ops task). On fresh `zse -l ticket
<id>`, before Zellij launches, `zse` creates the worktree at
`.claude/worktrees/<id>` on branch `$ZSE_BRANCH_USER/<id>` (e.g.
`juliusblank/PCS-14446`) when a `$ZSE_BRANCH_USER` is set — matching the
Taktile PR-branch convention from the first commit, so there's no need to
rename Claude Code's default `worktree-<id>` after the fact. The claude
pane then runs `zse-claude --own --worktree $ZELLIJ_SESSION_NAME`, which
reuses the pre-created worktree as-is and resumes the ticket's own
conversation after a pane restart. If `ZSE_BRANCH_USER` is empty or cwd isn't
a git repo, `zse` falls back silently to Claude Code's default naming.
Second `zse -l ticket <id>` with the same id is a no-op on worktree
creation and simply attaches a fresh claude in the same directory.

### review

A short-lived PR review with its own conversation (`--own`). On the first
start the pane opens with `/review:review $ZELLIJ_SESSION_NAME` as its first
user message (`--first-prompt`); after `zse stop` / `zse restore` it resumes
the conversation and does not run the review again. `$ZELLIJ_SESSION_NAME`
is `review-<repo>-pr<n>` (from `zse -l review <PR URL>`). To review new
pushes, run `/review:review $ZELLIJ_SESSION_NAME` again in the session. The
`review` command (`jbl-personal/review`, a local Claude Code marketplace
at `~/github/jbl-taktile/claude-skills`) handles PR checkout under
`.claude/worktrees/pr-<n>`. No tig pane — review is read-first, not
commit-first. Instead, the **CI pane (`zse-ci`)** under the shell redraws
`gh pr checks <n>` with the PR title every 30 s (`ZSE_CI_INTERVAL`), so new
pushes show up; `gh` uses HTTPS, no SSH. `q` quits it. `zse kill` in a review
session offers to remove `.claude/worktrees/pr-<n>`.

### daily

For the `~/github/jbl-taktile/daily-tasks` repo. Start it with `zse -l
daily` from the repo root. The right pane runs the repo's own
`scripts/tasks-pane`: an fzf picker over the open tasks from all
`vault/Daily/*.md` notes (Obsidian's Tasks query does not render in a
terminal, so the script aggregates them). Keys tick / drop a task in
place in the note it lives in; the list reloads when the vault changes.
The layout only places the pane — all vault logic lives in daily-tasks.
In a repo without `scripts/tasks-pane`, the pane prints a hint and
drops to zsh.

## CLI — `zse`

```
zse [-l USE_CASE] [-a AWS_PROFILE] [NAME]   start NAME, or attach if it runs
zse ls                                      list registered and running sessions
zse stop [NAME]                             stop a session, keep it registered
zse kill [NAME]                             end a session and clean up
zse restore [NAME...]                       start stopped sessions in the background
zse restart --all | NAME...                 stop running sessions, start them again
zse switch NAME                             switch to NAME (start it if stopped)
zse help
```

The CLI is plain zsh in `home/modules/zse.zsh`, sourced from `~/.zshrc`.

### Session registry

Zellij session serialization is **off** (`session_serialization false` in
`config.kdl`). Zellij resurrection restored the *leaf* process of each
pane, the old saved layout, and command panes suspended until Enter (see
SPEC row 31). Instead, `zse` keeps a registry, one file per session:

```
~/.local/state/zse/sessions/<name>     ($XDG_STATE_HOME)
    use_case=ticket
    dir=/Users/.../github/org/repo
    aws_profile=
    created=2026-10-16T09:00:00Z
    last_started=2026-10-16T11:00:00Z
```

`zse` writes it on every start; `zse kill` removes it. A session always
starts from the **current** layout file, and `zse-claude --own` resumes
the session's own conversation, so a stop / restore cycle (or a crash or
reboot) loses nothing.

### Commands

- **`zse [-l USE_CASE] [-a AWS_PROFILE] [NAME]`** — start or attach.
  - Running → attach (inside Zellij: switch in place). `-a` is ignored
    with a notice that shows the profile the session uses; AWS-expiry
    warning if it applies.
  - Registered but stopped → start it again with its registered use case,
    start directory and AWS profile (`-l` / `-a` override them). It works
    from any directory.
  - Unknown → start a new session in `$PWD`, through `assume` if `-a` is
    given. Inside Zellij, the new session starts in the background and
    `zse` switches to it (not with `-a`: start those outside Zellij).
  - An old EXITED session from before serialization was turned off is
    deleted first, so it does not come back with its old layout.
- **`zse ls`** — every registered session with use case, state, AWS flag
  and start directory. States: `running`, `stopped`, `orphan` (start
  directory is gone; `zse kill` it), plus `untracked` (a live Zellij
  session that zse did not start) and `old-exited` (a serialized session
  from before the registry).
- **`zse stop [NAME]`** — stop the session (`zellij kill-session`).
  Registry entry, worktree and Claude conversation stay. Default NAME: the
  current session.
- **`zse kill [NAME]`** — end the session. If the repo of its start
  directory has a `.claude/worktrees/<name>` worktree (review sessions:
  `pr-<n>`), it asks to remove it; it refuses when the worktree has
  uncommitted or unpushed changes. On removal it unlocks, removes, prunes,
  and deletes Claude's default `worktree-<name>` branch (a
  `$ZSE_BRANCH_USER/<name>` branch stays). Then it removes the AWS
  side-car, the welcome sentinel and the registry entry, and deletes the
  Zellij session (`zellij delete-session --force`). Default NAME: the
  current session.
- **`zse restore [NAME...]`** — start the given (default: all) registered,
  stopped sessions in the background (`zellij attach --create-background`).
  It skips orphans, and sessions with an AWS profile (`assume` needs the
  YubiKey): for those it prints the command to start them. Use it after a
  crash or a reboot.
- **`zse restart --all | NAME...`** — stop the running sessions, then
  `zse restore` them, so they pick up a new layout after `just deploy`.
  Conversations, worktrees and registry entries stay. It skips the current
  session (stopping it would end the command too; run it from another
  session or outside Zellij). `--all` takes every running registered
  session except those with an AWS profile, which keep running; a named
  AWS session is stopped and restore prints its start command.
- **`zse switch NAME`** — switch to NAME; restore it first if it is
  stopped. Inside Zellij it switches in place (`zellij action
  switch-session`), outside it attaches.

Options and names:

- `-l USE_CASE` — `code`, `project`, `ticket`, `review`, `daily`,
  `code-resume`. Default: the registered use case, else `$ZSE_LAYOUT`
  (devshells can bind a per-repo default), else `code`.
- `-a AWS_PROFILE` — start Zellij through the host's `assume` fn
  (`aws-vault exec <profile> -d 8h`, 2h for on-call write, with YubiKey
  TOTP on concinnity). Every pane inherits the credentials. If the session
  outlives them, panes silently use stale creds: on attach, `zse` reads a
  side-car at `~/.cache/zse/sessions/<name>.env` and warns when
  `AWS_SESSION_EXPIRATION` is within 15 min or past.
- `NAME` — default: `basename $PWD` (`zellij-<pid>` in a devshell that
  exports `name=nix-shell-env`). For `ticket`, the ticket ID; for
  `review`, a GitHub PR URL (`https://github.com/<owner>/<repo>/pull/<n>`):
  `zse` names the session `review-<repo>-pr<n>` and starts it in the
  local checkout at `~/github/<owner>/<repo>`, so the worktree lands in
  the right repo. The URL form is for drive-by reviews without a ticket.
  `ticket` / `review` layouts read the name from `$ZELLIJ_SESSION_NAME`.

zsh completion: verbs, `-l` use cases, and session names (running and
registered) for the positional NAME and for `stop` / `kill` / `restore` /
`switch`.

Deprecated aliases (they print a hint; removal in a later release):
`zsek` → `zse kill`, `zsek -k` → `zse stop`, `zss NAME` → `zse switch
NAME`, `zsep [NAME]` → `zse -l code-resume [NAME]`.

### Switching sessions quickly

1. **`Ctrl Space`** — a `shared` keybind that opens the Session Manager
   picker in a floating pane. One keystroke from any mode.
2. **`zse switch <name>`** — in-place switch when you know the name;
   `<TAB>` completes it.
3. **`Ctrl o d` → `zse <name>`** — detach, then attach again. Use it when
   you want the parent shell back.

## AWS handling

`zse -a <profile>` is the single surface for binding an AWS profile to a
Zellij session. It calls through to the host's own `assume` fn (defined
on concinnity in `hosts/concinnity/home.nix`); `zse` never speaks AWS
protocols or edits `~/.aws/config` directly. `~/.aws/config` on
concinnity is generated by the `taktile-infra generate-aws-config`
workflow — do not modify it in this repo.

`assume` on concinnity accepts `assume <profile> [-- CMD ARGS...]`. With
`--`, it `aws-vault exec`s the command and exits (no interactive subshell);
without, it drops into the usual interactive subshell. `zse -a` uses the
first form, writes the per-session AWS side-car from inside the subshell,
then `exec`s `zellij`.

Side-car layout:

```
~/.cache/zse/sessions/<name>.env
    AWS_PROFILE=<profile>
    AWS_SESSION_EXPIRATION=<RFC3339>
```

`zse` reads this on every attach to a running session and warns if the
expiration is within 15 min or past. `zse kill` deletes the side-car; `zse` deletes a stale side-car on first
check if the session no longer exists.

## Related

- `home/modules/zellij.nix` — the module (layouts, helper packages, config).
- `home/modules/zse.zsh` — the `zse` CLI.
- `docs/SPEC.md` roadmap row 26 — Zellij as the chosen pattern for
  Claude Code session terminal management.
