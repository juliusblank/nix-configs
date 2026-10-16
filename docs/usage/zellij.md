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
| **project** | `project.kdl` | tabs: master (code shape) + agents (full-screen) | master: `zse-claude --own`; agents: `claude agents` |
| **ticket** | `ticket.kdl` | claude · (shell · tig) · compact bar | `zse-claude --own --worktree $ZELLIJ_SESSION_NAME` |
| **review** | `review.kdl` | claude · (shell · CI) · compact bar (no tig) | `zse-claude "/review:review $ZELLIJ_SESSION_NAME"` (fresh) |
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

The `agents` tab in `project` stays bare `claude
agents` — it's a management view, not an interactive REPL.

Each claude pane also exports `ZSE_USE_CASE=<code|project|ticket|review|daily>`
(`code-resume` exports `code`). Plugins use it to tailor a session to its
layout: the `jbl-personal` `project` plugin has a `SessionStart` hook that
injects the master-session ground rules (`project/rules.md`: role,
phases, ADR change handling) when `ZSE_USE_CASE=project` and the cwd is
not a `.claude/worktrees/*` sub-session. The hook fires on startup,
resume, clear and compact, so the rules survive compaction. The rules
live in the plugin repo, so changing them needs no nix deploy.

Plus a `code-resume.kdl` variant that uses `claude --resume` (opens the
picker) instead of `--own` — used by `zsep`.

The source of truth is a Nix generator in `home/modules/zellij.nix`:
shared pane fragments (`barPane`, `shellTigColumn`, `threePaneBody`)
compose into the per-layout `.kdl` files on activation.

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
banner on resume. `zsek` deletes the sentinel so a reused session name
re-welcomes. `code` and `code-resume` have no banner — those shell panes
are plain zsh.

For `review`, the claude pane auto-sends `/review:review $NAME` on
create; the banner just reports what's running. For `ticket` and
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
- **agents**: full-screen `claude agents` for inspecting and dispatching
  background sessions.

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

A short-lived PR review. Fresh claude session (no `--continue`); the
pane opens with `/review:review $ZELLIJ_SESSION_NAME` as its first user message,
where `$ZELLIJ_SESSION_NAME` is `review-<repo>-pr<n>` (from `zse -l review <PR URL>`). The
`review` command (`jbl-personal/review`, a local Claude Code marketplace
at `~/github/jbl-taktile/claude-skills`) handles PR checkout under
`.claude/worktrees/pr-<n>`. No tig pane — review is read-first, not
commit-first. Instead, the **CI pane (`zse-ci`)** under the shell redraws
`gh pr checks <n>` with the PR title every 30 s (`ZSE_CI_INTERVAL`), so new
pushes show up; `gh` uses HTTPS, no SSH. `q` quits it. `zsek` in a review
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

## CLI — `zse`, `zsep`, `zsek`, `zss`

```
zse [-l USE_CASE] [-a AWS_PROFILE] [NAME]
zsep [NAME]
zsek [-k]
zss NAME
```

- `-l USE_CASE` — one of `code`, `project`, `ticket`, `review`, `daily`. Defaults
  to `$ZSE_LAYOUT` (devshells can bind a per-repo default), else `code`.
  zsh completion offers the five names.
- `-a AWS_PROFILE` — launches Zellij through the host's `assume` fn
  (`aws-vault exec <profile> -d 8h`, 2h for on-call write, with YubiKey
  TOTP on concinnity).
  Every pane inherits the aws-vault subshell credentials. If the Zellij
  session outlives the 8 h window, panes silently use stale creds — `zse`
  on attach reads a per-session side-car at
  `~/.cache/zse/sessions/<name>.env` (written at session creation; auto-
  deleted when the session no longer exists) and prints a warning when
  `AWS_SESSION_EXPIRATION` is within 15 min or past. `-a` on an attach is
  a no-op with a one-line notice showing the profile the session actually
  uses.
- `NAME` — defaults to `basename $PWD` (or `zellij-<pid>` when that comes
  back empty, e.g. in a devshell that exports `name=nix-shell-env`). For
  `ticket`, pass the ticket ID; for `review`, pass a full GitHub PR URL
  (`https://github.com/<owner>/<repo>/pull/<n>`) or the raw
  `review-<repo>-pr<n>` form the URL expands to. On a URL, `zse` parses
  `<owner>`, `<repo>`, `<n>` and sets the Zellij session name to
  `review-<repo>-pr<n>` so the session list carries the repo + PR
  context in one glance; Zellij is launched from the matching local
  checkout at `~/github/<owner>/<repo>` so the worktree lands in the
  right repo. The URL form is for drive-by reviews with no linked
  ticket — the ticket flow is still preferred when a ticket exists.
  `ticket` / `review` layouts read the name from `$ZELLIJ_SESSION_NAME`
  at pane start. Welcome banner + tab name display a human-friendly
  `[review] <repo> PR #<n>` label via `zellij action rename-tab`.
- `zsep [NAME]` — like `zse` but uses the `code-resume` layout, which opens
  Claude's `--resume` picker. Only applies to the `code` shape; other use
  cases have no resume variant (ticket reuses its worktree, review is
  fresh, project's agent dispatcher is live).
- `zsek` — **end** the current Zellij session: kill **and delete** it (`zellij
  delete-session --force`), so a reused name starts fresh from the current
  layout file instead of resurrecting the old one. `zsek -k` only **stops**
  it (`zellij kill-session`, no cleanup): it stays EXITED and `zse <name>`
  resurrects it with its saved layout. `zsek -h` prints the difference. If the session name matches a
  `.claude/worktrees/<name>` directory under the current repo, prompts
  for worktree removal, blocks it with a message when uncommitted or
  unpushed state is present, otherwise unlocks + removes + prunes + drops
  the auto-created `worktree-<name>` branch. Also deletes the AWS
  side-car.
- `zss NAME` — switch the current session in place to `NAME` without
  detaching (`zellij action switch-session`). Faster than opening the
  picker when you already know the target. Pairs with the `_zse_sessions`
  completer, so `zss <TAB>` lists every live/exited session; `zse <TAB>`
  and `zsep <TAB>` complete the positional NAME the same way.

### Switching sessions quickly

Three ways, in order of effort:

1. **`Ctrl Space`** — a `shared` keybind that opens the Session Manager
   picker directly in a floating pane. One keystroke from any mode.
2. **`zss <session> <enter>`** — in-place switch when you already know the
   name; `zss <TAB>` completes session names.
3. **`Ctrl o d` → `zse <name>`** — the old flow: detach then re-attach.
   Useful when you want the parent shell back.

Session state matrix for `zse`:

| State | Behaviour |
|---|---|
| **live** | attach; `-a` ignored with notice; AWS-expiry warning if applicable |
| **exited** (resurrectable) | attach — Zellij resurrects the **saved** layout + cwds (not the current layout file — to pick up layout changes, delete the session with `zsek` or `zellij delete-session` first); processes start fresh (`zse-claude --own` resumes the session's own conversation; ticket's `--worktree` reuses) |
| **none** | create fresh session with the chosen layout, through `assume` if `-a` was given |

The use case for a session is not persisted — it is implicit in the
layout chosen at creation and (for ticket) reflected in the presence of
a `.claude/worktrees/<name>` dir, which `zsek` keys off. Review
worktrees are named `pr-<n>`, not after the `review-<repo>-pr<n>`
session, so `zsek` does not remove them yet (SPEC roadmap row 30).

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

`zse` reads this on every `zse <existing-session>` and `zsep <existing-session>`
and warns if the expiration is within 15 min or past. `zsek` deletes the
side-car when it kills a session; `zse` deletes a stale side-car on first
check if the session no longer exists.

## Related

- `home/modules/zellij.nix` — the module (layouts, package, zsh fns).
- `docs/SPEC.md` roadmap row 26 — Zellij as the chosen pattern for
  Claude Code session terminal management.
