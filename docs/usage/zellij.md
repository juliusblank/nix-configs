# Zellij — Claude Code session terminal management

This is how the `nix-configs` repo organises Claude Code work in a single
Ghostty window. One Zellij session per Claude workflow, four named layouts
picked by use case.

## Use cases and layouts

Zellij session name = Claude workflow name = worktree / branch name
(project slug, ticket ID or `pr-<number>`).

| Use case | Layout file | Pane shape | Claude command |
|---|---|---|---|
| **code** (default) | `code.kdl` | claude · (shell · tig) · status bar | `claude --continue` |
| **project** | `project.kdl` | tabs: master (code shape) + agents (full-screen) | master: `claude --continue`; agents: `claude agents` |
| **ticket** | `ticket.kdl` | claude · (shell · tig) · status bar | `claude --worktree $ZR_SESSION_NAME` |
| **review** | `review.kdl` | claude · shell · status bar (no tig) | `claude "/review $ZR_SESSION_NAME"` |

Plus a `code-resume.kdl` variant that uses `claude --resume` (opens the
picker) instead of `--continue` — used by `zrp`.

The source of truth is a Nix generator in `home/modules/zellij.nix`:
shared pane fragments (`statusBarPane`, `shellTigColumn`, `threePaneBody`)
compose into the per-layout `.kdl` files on activation.

`ticket` and `review` reference `$ZELLIJ_SESSION_NAME`, an env var Zellij
sets per pane at session creation. Each ticket / review session sees its
own name without the layout files needing to be rendered per session.

## Welcome banners

The `ticket`, `project`, and `review` layouts show a one-time banner in
the shell pane on fresh session creation, printed by the `zr-welcome`
helper (installed via home-manager):

```
┏━━━━━━━━━━━┓
┃  TICKET   ┃
┗━━━━━━━━━━━┛
→ /ticket:start PCS-13558 — prime ticket context (jbl-personal/ticket)
```

A sentinel at `~/.cache/zr/sessions/<name>.welcomed` suppresses the
banner on resume. `zrk` deletes the sentinel so a reused session name
re-welcomes. `code` and `code-resume` have no banner — those shell panes
are plain zsh.

For `review`, the claude pane auto-sends `/review:review $NAME` on
create; the banner just reports what's running. For `ticket` and
`project`, the user invokes the kickoff command manually from the
banner's hint.

## Use-case specifics

### code

Everything the current `zr` session does today: claude auto-resumes the
most recent conversation in cwd, a shell to run commands, a tig status
view that doesn't poll (so no periodic 1Password SSH-agent prompts).

### project

A long-running "master" plan that dispatches ticket sub-sessions via
`claude agents`. Two explicit tabs:

- **master** (default focus): `claude --continue` from the repo root.
  Since worktree-based agent sub-sessions record their conversations
  under the worktree's cwd (`~/.claude/projects/-...--claude-worktrees-<name>/`),
  not the parent, repo-root `--continue` always picks up master.
- **agents**: full-screen `claude agents` for inspecting and dispatching
  background sessions.

The status bar renders in both tabs via `default_tab_template`.

### ticket

A single standalone ticket (bug fix, ops task). The claude pane runs
`claude --worktree $ZR_SESSION_NAME` — reuses an existing worktree with
that name, or creates one at `.claude/worktrees/<id>` on a branch named
`worktree-<id>`. Second `zr -l ticket <id>` with the same id is a no-op
on worktree creation and simply attaches a fresh claude in the same
directory.

### review

A short-lived PR review. Fresh claude session (no `--continue`); the
pane opens with `/review $ZR_SESSION_NAME` as its first user message,
where `$ZR_SESSION_NAME` is the PR number convention (`pr-<n>`). The
`review` skill (in `taktile-skills`, not shipped by this repo) handles
PR checkout under `.claude/worktrees/pr-<n>`. No tig pane — review is
read-first, not commit-first.

## CLI — `zr`, `zrp`, `zrk`

```
zr [-l USE_CASE] [-a AWS_PROFILE] [NAME]
zrp [NAME]
zrk
```

- `-l USE_CASE` — one of `code`, `project`, `ticket`, `review`. Defaults
  to `$ZR_LAYOUT` (devshells can bind a per-repo default), else `code`.
  zsh completion offers the four names.
- `-a AWS_PROFILE` — launches Zellij through the host's `assume` fn
  (`aws-vault exec <profile> -d 8h` with YubiKey TOTP on concinnity).
  Every pane inherits the aws-vault subshell credentials. If the Zellij
  session outlives the 8 h window, panes silently use stale creds — `zr`
  on attach reads a per-session side-car at
  `~/.cache/zr/sessions/<name>.env` (written at session creation; auto-
  deleted when the session no longer exists) and prints a warning when
  `AWS_SESSION_EXPIRATION` is within 15 min or past. `-a` on an attach is
  a no-op with a one-line notice showing the profile the session actually
  uses.
- `NAME` — defaults to `basename $PWD`. For `ticket`, pass the ticket ID;
  for `review`, pass `pr-<n>`. `ticket` / `review` layouts read the name
  from `$ZELLIJ_SESSION_NAME` at pane start.
- `zrp [NAME]` — like `zr` but uses the `code-resume` layout, which opens
  Claude's `--resume` picker. Only applies to the `code` shape; other use
  cases have no resume variant (ticket reuses its worktree, review is
  fresh, project's agent dispatcher is live).
- `zrk` — kill the current Zellij session. If the session name matches a
  `.claude/worktrees/<name>` directory under the current repo, prompts
  for worktree removal, blocks it with a message when uncommitted or
  unpushed state is present, otherwise unlocks + removes + prunes + drops
  the auto-created `worktree-<name>` branch. Also deletes the AWS
  side-car.

Session state matrix for `zr`:

| State | Behaviour |
|---|---|
| **live** | attach; `-a` ignored with notice; AWS-expiry warning if applicable |
| **exited** (resurrectable) | attach — Zellij resurrects layout + cwds; processes start fresh (claude's `--continue` picks up the conversation; ticket's `--worktree` reuses) |
| **none** | create fresh session with the chosen layout, through `assume` if `-a` was given |

The use case for a session is not persisted — it is implicit in the
layout chosen at creation and (for ticket / review) reflected in the
presence of a `.claude/worktrees/<name>` dir, which `zrk` keys off.

## AWS handling

`zr -a <profile>` is the single surface for binding an AWS profile to a
Zellij session. It calls through to the host's own `assume` fn (defined
on concinnity in `hosts/concinnity/home.nix`); `zr` never speaks AWS
protocols or edits `~/.aws/config` directly. `~/.aws/config` on
concinnity is generated by the `taktile-infra generate-aws-config`
workflow — do not modify it in this repo.

`assume` on concinnity accepts `assume <profile> [-- CMD ARGS...]`. With
`--`, it `aws-vault exec`s the command and exits (no interactive subshell);
without, it drops into the usual interactive subshell. `zr -a` uses the
first form, writes the per-session AWS side-car from inside the subshell,
then `exec`s `zellij`.

Side-car layout:

```
~/.cache/zr/sessions/<name>.env
    AWS_PROFILE=<profile>
    AWS_SESSION_EXPIRATION=<RFC3339>
```

`zr` reads this on every `zr <existing-session>` and `zrp <existing-session>`
and warns if the expiration is within 15 min or past. `zrk` deletes the
side-car when it kills a session; `zr` deletes a stale side-car on first
check if the session no longer exists.

## Related

- `home/modules/zellij.nix` — the module (layouts, package, zsh fns).
- `docs/SPEC.md` roadmap row 26 — Zellij as the chosen pattern for
  Claude Code session terminal management.
