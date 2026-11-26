# Zellij — Claude Code session terminal management

This is how the `nix-configs` repo organises Claude Code work in a single
Ghostty window. One Zellij session per Claude workflow, five use-case layouts
picked by use case.

## Use cases and layouts

Session names follow `<type>-<repo>-<id>-<hint>` (ASCII, at most 40 chars):

| Use case | Session name | Worktree | Branch |
|---|---|---|---|
| ticket | `tkt-<ID>-<hint>` | `.claude/worktrees/<ID>` | `<prefix>/<ID>` |
| review | `rev-<repo>-<n>-<hint>` | `.claude/worktrees/pr-<n>` | the PR's |
| review-doc | `doc-<title>-<id8>` (Notion) / `doc-<repo>-<n>` (PR) | PR: `pr-<n>` | — |
| project | `proj-<slug>` | — (repo root) | — |
| explore | `exp-<slug>` | `.claude/worktrees/<slug>` | `explore/<slug>` |
| code, daily | `<dir name>` | — | — |

`<repo>` is a short name: a map in `home/modules/zellij.nix` (`zseRepoShort`:
`workspace-services` → `ws`, `taktile-infra` → `infra`, …), else a rule
(drop `taktile-`, initials for 3+ parts, else the first 8 chars). The **hint**
is up to 3 short words that remind you what the session is about. For a new
ticket, `zse` reads the Linear title (one `claude -p` call with Haiku through
the Linear connector, about 10 s); for a review, the PR title (`gh`) and asks
Haiku for the hint. In a terminal it shows the title and lets you edit the
hint (Enter accepts, empty = none); `-t HINT` skips both. Without Claude, a
rule makes the hint from the title.

The name is only a label. What a session is about lives in the registry as
**name keys** (`ticket`, `pr`, `owner`, `repo`, `slug`, `wt`, `url`, `title`,
`hint`, `conv`); the panes read them with `zse-meta KEY`. Sessions from before
the name schema (`PCS-123`, `review-<repo>-pr<n>`, `review-doc-…`, bare slugs)
keep working: `zse-meta` falls back to the old name parsing. `zse migrate`
gives them the new names.

| Use case | Layout file | Pane shape | Claude command |
|---|---|---|---|
| **code** (default) | `code.kdl` | claude · (shell · tig) · compact bar | `zse-claude --own` |
| **project** | `project.kdl` | tabs: master (claude · (shell · (git \| agents status))) + agents (full-screen) | master: `zse-claude --own`; agents: `claude agents --cwd <repo>` |
| **ticket** | `ticket.kdl` | claude · (shell · tig) · compact bar | `zse-claude --own --worktree <ID>` (`zse-meta wt`) |
| **review** | `review.kdl` | claude · (shell · CI) · compact bar (no tig) | `zse-claude --own --first-prompt "/tktl-eng-delivery:review <PR URL>"` (`zse-meta url`; review on first start; own conversation) |
| **review-doc** | `review-doc.kdl` | claude · shell · compact bar (no tig, no CI) | `zse-claude --own --first-prompt "/tktl-eng-delivery:review-doc <url>"` (`zse-meta url`; review on first start; own conversation) |
| **daily** | `daily.kdl` | claude · tasks (40 %) · compact bar | `zse-claude --own`; tasks pane runs `scripts/tasks-pane` |
| **explore** | `explore.kdl` | claude · (shell · exploration) · compact bar (no tig) | `zse-claude --own --first-prompt "/explore status <slug>" --worktree <slug>` |

Every interactive claude pane runs `zse-claude` (installed by the
module), which adds `--remote-control "$ZELLIJ_SESSION_NAME"` (the session
is addressable from the account's other Remote-Control-enrolled devices
under the same name the Zellij session has locally) and `--name
"$ZELLIJ_SESSION_NAME"` (prompt box, `/resume` picker, terminal title).

`zse-claude --own` gives each Zellij session **its own conversation**: the
conversation ID is the registry's `conv` (set by `zse migrate`), else a UUID
derived from the session name and the pane's start directory. If a transcript with that ID exists, the pane resumes it
(`--resume <id>`); otherwise it starts a fresh conversation under that ID
(`--session-id <id>`). This replaces `claude --continue`, which resumes
the most recent conversation **in the directory** — so a new `project`
master in a repo where a `code` session ran before picked up that
session's conversation. Old conversations stay reachable via `/resume`.

The `agents` tab in `project` runs `claude agents --cwd <repo>` — a
management view, not an interactive REPL.

Each claude pane also exports `ZSE_USE_CASE=<code|project|ticket|review|daily|explore>`
(`code-resume` exports `code`) for zse's own scripts. The `project`, `ticket`,
`review` and `review-doc` panes also export `DELIVERY_SESSION=<use case>`, the
variable the delivery plugins (`project`, `ticket`, `review`) key off: the
`project` plugin has a `SessionStart` hook that injects the master-session
ground rules (`project/rules.md` and a mode file) when
`DELIVERY_SESSION=project` and the cwd is not a `.claude/worktrees/*`
sub-session. The hook fires on startup,
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

The layouts are shared by all sessions of a use case: each pane reads its
session's keys at start (`zse-meta`, from `$ZELLIJ_SESSION_NAME`, which Zellij
sets per pane), so no layout file is rendered per session.

**Shell pane (`zse-shell`).** In `ticket`, `explore` and `review` sessions the
shell pane moves into the session's worktree (it waits up to 30 s, for review
180 s while `/tktl-eng-delivery:review` checks the PR out; Enter skips) and
checks it: a red warning names the directory and branch when it is not in the
worktree.

## Welcome banners

The `ticket`, `project`, `review` and `explore` layouts show a one-time banner in
the shell pane on fresh session creation, printed by the `zse-welcome`
helper (installed via home-manager):

```
┏━━━━━━━━━━━┓
┃  TICKET   ┃
┗━━━━━━━━━━━┛
→ /tktl-eng-delivery:ticket-start PCS-13558 — prime ticket context (tktl-eng-delivery)
```

A sentinel at `~/.cache/zse/sessions/<name>.welcomed` suppresses the
banner on resume. `zse kill` deletes the sentinel so a reused session name
re-welcomes. `code` and `code-resume` have no banner — those shell panes
are plain zsh.

For `review`, the claude pane auto-sends `/tktl-eng-delivery:review <PR URL>` on
the first start (not on restore); the banner just reports what's running. The
same holds for `explore` with `/explore status <slug>`. The tab is renamed to
`[ticket] <ID> <hint>`, `[review] <repo> PR #<n> <hint>`, `[project] <slug>`, …. For `ticket` and
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

A single standalone ticket (bug fix, ops task). `zse -l ticket <ID>` names
the session `tkt-<ID>-<hint>` and, before Zellij launches, creates the
worktree `.claude/worktrees/<ID>` with the `tktl-eng-delivery` plugin's
`scripts/worktree.sh`: it fetches origin, starts a new branch
`<delivery.branchPrefix>/<ID>` (e.g. `juliusblank/PCS-14446`) at
`origin/<default>` (never at the main checkout's HEAD), checks the result, and
warns about foreign commits on a reused branch. Without the plugin, `zse` does
the same itself on `$ZSE_BRANCH_USER/<ID>`. A failed fetch stops the start
(no stale base). The claude pane runs `zse-claude --own --worktree <ID>`,
which reuses the worktree and resumes the ticket's own conversation. Later,
`zse <ID>` (or `zse -l ticket <ID>`) finds the session by its ticket ID.

### review

A short-lived PR review with its own conversation (`--own`). On the first
start the pane opens with `/tktl-eng-delivery:review <PR URL>` as its first
user message (`--first-prompt`); after `zse stop` / `zse restore` it resumes
the conversation and does not run the review again. The session is
`rev-<repo>-<n>-<hint>` (from `zse -l review <PR URL>`); the same URL later
finds it again (by owner, repo and PR number). To review new pushes, run
`/tktl-eng-delivery:review <PR URL>` again in the session. The
`review` command (plugin `tktl-eng-delivery` from the `taktile-skills`
marketplace) handles PR checkout under
`.claude/worktrees/pr-<n>`. An old-style `review-<repo>-pr<n>` session has no
owner in its name: if it belongs to another checkout (same repo name, other
owner), `zse` stops with an error instead of resuming that review. No tig pane — review is read-first, not
commit-first. Instead, the **CI pane (`zse-ci`)** under the shell redraws
`gh pr checks <n>` with the PR title every 30 s (`ZSE_CI_INTERVAL`), so new
pushes show up; `gh` uses HTTPS, no SSH. `q` quits it. `zse kill` in a review
session offers to remove `.claude/worktrees/pr-<n>`.

### review-doc

A design doc review (ADR or PEP) with its own conversation. `zse -l review-doc
<URL>` takes a Notion page URL or a GitHub PR URL. A Notion URL names the
session `doc-<title>-<id8>` (the page title from the URL, lower case, at
most 34 chars, so the Zellij socket path stays within the macOS limit, plus the
first 8 chars of the page ID, so pages with the same
title do not share a session; only the ID part when the URL has no title) and
starts it in the current directory. If a registered session with that name
belongs to another page, or (for a PR URL) to another checkout, `zse` stops with
an error instead of resuming the other review. `review` and `review-doc`
sessions for the same PR share the `pr-<n>` worktree; `zse kill` keeps it while
the other session is still registered. A PR URL names it `doc-<repo>-<n>` and starts it in
`~/github/<owner>/<repo>`, as for `review`. `zse` keeps the URL in the session
registry (`url=`); on the first start the claude pane sends `/tktl-eng-delivery:review-doc <url>`
(`zse-meta url` reads it back), and a restored session resumes without a new
review. `/tktl-eng-delivery:review-doc` (`tktl-eng-delivery`) ranks the findings by severity and
then interviews you for each one: you write the comment, or start from a
generated draft, or skip. Nothing is posted without your OK. The tab reads
`[review-doc] <slug>`. No tig and no CI pane.

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

### explore

For private explorations in `nix-configs` (`docs/SPEC.md` → *Explorations*):
goal-first topics worked in short iterations with the `/explore` repo skill
(`new · iterate · status · close`). Start one with `zse -l explore <slug>`
from the `nix-configs` checkout; the session is `exp-<slug>`. `zse` pre-creates the worktree
`.claude/worktrees/<slug>` on branch `explore/<slug>` from the fetched
`origin/<default>` (reused if it exists);
that branch is the exploration's PR branch. The claude pane works in the
worktree with its own conversation and sends `/explore status <slug>` on the
first start, so a new session opens with the goal, the current iteration, the
remaining budget and the next step. The right column holds the shell and the
**exploration pane** (`zse-explore`): `docs/explorations/<slug>.md` of the
worktree, rendered by `bat`, cut to the pane height (header, brief and goal
stay in view), redrawn every `$ZSE_EXPLORE_INTERVAL` seconds (default 10);
`q` quits. For a new idea without a file yet, the pane shows a hint — run
`/explore new <idea>` in the claude pane. `zse kill <slug>` removes the
worktree but keeps the `explore/<slug>` branch. The skill lives only in this
repo, so the layout does nothing elsewhere (work repos are not affected).

## CLI — `zse`

```
zse [-l USE_CASE] [-a AWS_PROFILE] [-t HINT] [NAME]
                                            start NAME, or attach if it runs
zse ls                                      list registered and running sessions
zse stop [--all | NAME]                     stop a session, keep it registered
zse kill [NAME]                             end a session and clean up
zse restore [NAME...]                       start stopped sessions in the background
zse restart --all | NAME...                 stop running sessions, start them again
zse switch NAME                             switch to NAME (start it if stopped)
zse migrate NAME... | --all [--force]       give old-style sessions the new names
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
    names=2                      # name keys, for sessions with the new names:
    ticket=PCS-123
    wt=PCS-123
    title=Fix cache TTL for entity reads
    hint=cache-ttl
```

`zse` writes it on every start; `zse kill` removes it. A session always
starts from the **current** layout file, and `zse-claude --own` resumes
the session's own conversation, so a stop / restore cycle (or a crash or
reboot) loses nothing.

`zse` removes Claude Code's session markers (`CLAUDECODE`, `CLAUDE_CODE_CHILD_SESSION`,
`CLAUDE_CODE_SESSION_ID`, the messaging socket and token, …) before it starts a
Zellij server. So a Claude session may run `zse restart` / `zse restore` for you:
without this, every pane of the new session would inherit the markers, and its
claude would not save its conversation ("Transcript saving is off — inherited
CLAUDE_CODE_CHILD_SESSION marker").

Zellij's own sockets live in `~/.cache/zj` (`ZELLIJ_SOCKET_DIR`, set in
`home/modules/zellij.nix`). The default `$TMPDIR` path is so long on macOS
that Zellij 0.45 limits session names to 24 characters, too short for
`rev-<repo>-<n>-<hint>` (the short dir allows about 55; zse keeps names at
40). A client with a different `ZELLIJ_SOCKET_DIR` (or
an old shell that has not picked up the variable) does not see the
sessions: stop them with `zse stop --all` before you change it, and run
`zse restore` from a new terminal after.

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
  current session. `--all` stops every running session except the current
  one (use it before a deploy that changes the Zellij version or socket
  dir; `zse restore` brings them back).
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
- **`zse migrate NAME... | --all [--force]`** — give sessions from before the
  name schema their new names: `PCS-123` → `tkt-PCS-123-<hint>`,
  `review-<repo>-pr<n>` → `rev-<repo>-<n>-<hint>`, `review-doc-…` → `doc-…`,
  project `<slug>` → `proj-<slug>`, explore `<slug>` → `exp-<slug>` (hints as
  for a new session). The worktree and branch stay, and `conv` keeps the
  conversation ID of the old name, so Claude resumes the same conversation.
  The registry file, AWS side-car and welcome sentinel are renamed. A running
  session is stopped (it asks; `--force` does not), renamed and restored;
  sessions with an AWS profile are not restored. Lost, as with `zse restart`:
  scrollback and pane state.

`stop`, `kill`, `switch` and `zse NAME` also accept a ticket ID or a project
/ explore slug for a session with the new names (`zse kill PCS-123`).

Options and names:

- `-l USE_CASE` — `code`, `project`, `ticket`, `review`, `review-doc`,
  `daily`, `explore`, `code-resume`. Default: the registered use case, else `$ZSE_LAYOUT`
  (devshells can bind a per-repo default), else `code`.
- `-a AWS_PROFILE` — start Zellij through the host's `assume` fn
  (`aws-vault exec <profile> -d 8h`, 2h for on-call write, with YubiKey
  TOTP on concinnity). Every pane inherits the credentials. If the session
  outlives them, panes silently use stale creds: on attach, `zse` reads a
  side-car at `~/.cache/zse/sessions/<name>.env` and warns when
  `AWS_SESSION_EXPIRATION` is within 15 min or past.
- `-t HINT` — the hint in a new session's name; skips Claude and the
  prompt. `-t ''` means no hint.
- `NAME` — default: `basename $PWD` (`zellij-<pid>` in a devshell that
  exports `name=nix-shell-env`). For `ticket`, the ticket ID; for `project`
  and `explore`, the slug; for
  `review`, a GitHub PR URL (`https://github.com/<owner>/<repo>/pull/<n>`):
  `zse` names the session `rev-<repo>-<n>-<hint>` and starts it in the
  local checkout at `~/github/<owner>/<repo>`, so the worktree lands in
  the right repo. The URL form is for drive-by reviews without a ticket.
  For `review-doc`, a Notion page URL or a GitHub PR URL (see
  [review-doc](#review-doc)).

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
