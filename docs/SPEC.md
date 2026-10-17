# Nix Config — Specification

> This is a living document. It serves as the single source of truth for what this
> repo manages, and as prompt context for AI-assisted development.

## Goals

- **Consistent tooling** across all personal machines (macOS + Linux)
- **Reproducible** — any machine can be (re)built from this repo
- **Simple** — minimal nix knowledge needed for day-to-day use
- **Secure** — secrets encrypted at rest, no long-lived credentials in CI

## Repo Scope & Philosophy

This is a **monorepo for all personal system configuration and tooling**. When in doubt about whether something belongs here, the rule is: if it configures how you work, it belongs here.

**Lives in this repo:**
- System config (nix-darwin, NixOS, home-manager)
- Dotfiles and shell setup
- Infrastructure (AWS, GitHub, CI)
- Personal automation scripts and tooling (e.g. DJ toolchain, backup)
- Shared development conventions and AI assistant configuration

**Gets its own repo:**
- Project-specific code with its own lifecycle (apps, services, libraries)
- Things published as standalone open-source tools

**Exceptions** are fine when a tool's config is so tightly coupled to a specific project that it has no meaning outside of it. Default to keeping things here.

## Roadmap

The roadmap is the single prioritized backlog for this repo. It is reviewed periodically to stay aligned with inline planned notes throughout this spec and to adapt at a higher planning level. Inline notes provide the *why* and *how*; this list provides the *what* and *when*.

> **Review cadence:** revisit priorities whenever the list grows significantly, a major topic is completed, or the direction shifts.

### Active priorities

**Project conventions & structure** is a cross-cutting concern — improved continuously alongside all other work rather than as a discrete item.

| # | Item | Notes |
|---|---|---|
| 1 | Pre-commit hooks (`nixfmt-rfc-style`) | Done — nixfmt (staged .nix), tofu fmt (staged .tf), flake.lock consistency check |
| 2 | Branch + PR workflow with squash merges | Done — squash-only, PRs required, admins enforced |
| 3 | GitHub Actions CI workflow (`nix flake check`) | Done — path-aware jobs via `dorny/paths-filter`; `check-flake` (macos-14) only runs when nix files change, builds serenity and concinnity in parallel matrix jobs; `validate-release` runs on `chore/release-*` branches; `ci-passed` fan-in is the single required status check; `push-cache` matrix pushes both host closures to S3 on same-repo PRs and on merge to main |
| 4 | `tf-apply` guardrails | Done — hard block if not on `main` and working tree is dirty; soft warn (warn + require Enter) if not on `main` but tree is clean; on `main`, runs without interruption. `tf-plan` prints a warning when not on `main`. CI bypasses naturally (always clean, always on main). |
| 5 | `tf-plan` / `tf-apply` plan-to-file workflow | Done — `tf-plan` saves `tofu plan -out=tfplan`; `tf-apply` requires the plan file, runs `tofu apply tfplan`, then deletes it. Apply is deterministic (no re-evaluation). `tf-apply` exits with an error if no plan file exists. |
| 6 | Automated CI/CD for infrastructure | Done — `.github/workflows/infra.yml` triggers on `terraform/**` changes. On PR: fresh `tofu plan`, output posted as a PR comment (collapsed, truncated at 60 KB). On merge to `main`: fresh plan + apply in one job. AWS via OIDC; GitHub provider token fetched live from 1Password via `1password/load-secrets-action` on every run (SA: `github-actions-nix-configs`, vault: `infrastructure`). OIDC role extended with scoped policies: tofu state access, state backend management, IAM resource management, and nix cache bucket management (`terraform/iam-ci.tf`), plus nix cache read/write (`terraform/oidc.tf`). `OP_SERVICE_ACCOUNT_TOKEN` secret managed by terraform; SA token stored at `op://infrastructure/github-actions-nix-configs/token`. |
| 7 | Infrastructure tests | Validate OpenTofu modules with automated tests (candidate: Terratest or `tofu test`). Cover at minimum: S3 bucket exists and is private, IAM role trust policy is correctly scoped, OIDC provider URL is correct. Depends on #6. |
| 8 | Nix cache activation | Done — S3 bucket configured public-read; CI `push-cache` matrix pushes both host closures on same-repo PRs and on merge to main; signing key generated and stored in 1Password; public key and substituters in **`hosts/serenity/configuration.nix`** via **`nix.settings`**; serenity deployed with cache config active; cache seeded continuously by PR CI. |
| 9 | Changelog via `git-cliff` | Done — `cliff.toml` at repo root; `release.yml` workflow_dispatch creates a CalVer tag (`v<year>.<month>.<n>`), regenerates `CHANGELOG.md` under the new tag via `orhun/git-cliff-action`, and opens a release PR. The per-commit pre-commit regen was removed (caused merge conflicts on every PR without adding information); run `just changelog` for a manual preview. |
| 10 | Backup — serenity user data to S3 | Music, photos, projects; restore verification required |
| 11 | `concinnity` host config | In progress — work MacBook (Apple Silicon). Shared layers (`common.nix`, `darwin.nix`) reused; host-specific config isolates work identity, SSH keys, and secrets. Work clones under `~/github/taktile-org/`; `nix-configs` under `~/github/juliusblank/nix-configs` on all macOS hosts. GUI apps managed by company software distribution; nix-homebrew additive-only. Dev shells for work repos live in a separate work GitHub repo, activated via nix-direnv. Bootstrap + isolation: `README.md`, *Serenity and concinnity isolation* below. |
| 12 | AWS IAM Identity Center migration | In progress — Granted adopted for local AWS access. `granted` installed via Homebrew on serenity and nix `home.packages` on concinnity. `awscli2` system-wide via `home/darwin.nix`. Granted module at `home/modules/granted.nix` (`custom.granted.enable`). Firefox managed by home-manager via NUR on both hosts: `multi-account-containers` (named containers per AWS account), `open-url-in-container` (handles `ext+container:` protocol from `login` function), `granted` (AWS console session management); serenity additionally has `onepassword-password-manager`. IAM keys stored in 1Password; `op-credential-process` (nix-managed wrapper) handles `GetSessionToken` with YubiKey MFA and caches sessions in 1Password — zero credentials on disk. On concinnity, `assume <profile>` runs `aws-vault exec` (8h; 2h for `*on-call-engineer-write*`; `-- CMD` form for one command). aws-vault uses the 1Password desktop backend (`op-desktop`) and `ykman` as the MFA prompt. `login <profile>` opens the console in a Firefox container the same way. Profiles that use `op-credential-process` go through `grassume` (`assumego`). Next: configure SSO profiles. |
| 13 | AWS CLI credential management | Done — `awscli2` system-wide via `home/darwin.nix`. `~/.aws/config` managed by `home/modules/aws.nix` (`custom.aws.enable`) on serenity; manually managed on concinnity (generated by work GitHub workflow). `personal-nix-configs-infra` profile on serenity uses `credential_process` backed by 1Password (`op://infrastructure/personal-nix-configs-infra/`); concinnity uses `op-credential-process` (nix-managed, fetches IAM keys from 1Password, does `GetSessionToken` with YubiKey MFA, caches session in 1Password). devShell uses `AWS_CONFIG_FILE=$HOME/.aws/config`, `AWS_PROFILE=personal-nix-configs-infra`; CI overrides via `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` env vars (OIDC). Serenity: `assume` shell alias via `granted.nix` module. Concinnity: `assume <profile>` runs `aws-vault exec` (8h; 2h for `*on-call-engineer-write*`; `-- CMD` form for one command). aws-vault uses the 1Password desktop backend (`op-desktop`) and `ykman` as the MFA prompt. `login <profile>` opens the console in a Firefox container the same way. Profiles that use `op-credential-process` go through `grassume` (`assumego`). |
| 14 | Tool setup & dotfiles consolidation | Review old repos step by step |
| 15 | DJ toolchain — rekordbox automation | Process improvements, scripts |
| 16 | Rekordbox MCP server | Scope and project home TBD |
| 17 | `pi-moodpi` host config | Lower urgency |
| 18 | nixpkgs upgrade to 25.11 | Done — bumped `nixpkgs` to `nixpkgs-25.11-darwin`, `nix-darwin` to `nix-darwin-25.11`, `home-manager` to `release-25.11`. Enables declarative Firefox extensions on macOS (home-manager PR #6913). nix-homebrew updated to 5.1.10 (pin removed); homebrew-cask unpinned. Next upgrade: 26.05 (end of May 2026); retry `git-hooks.nix` / `pre-commit-hooks.nix`. |
| 19 | Terraform state bucket + DynamoDB under tofu management | Done — `terraform/state-backend.tf` defines both resources; `just tf-import-backend` imports them after initial bootstrap; `setup-terraform-backend` now prompts to run the import step |
| 20 | Separate infra repo | Move IAM Identity Center, DNSimple, Ionos, and other account-level infrastructure out of this repo into a dedicated `infra` repo. Keep in `nix-configs/terraform/`: nix cache bucket, state backend, GitHub repo settings, OIDC role for this repo's CI, and `personal-nix-configs-infra` IAM user. The infra repo becomes the prerequisite for completing #12 (IAM IC migration). |
| 21 | ghostty setup from work laptop | Done — `home/ghostty.nix` declares full Ghostty config (font, theme, opacity, keybinds, shell integration) applied to both hosts via `home/darwin.nix`. Package set to `null` on macOS (app installed via Homebrew cask on serenity; IRU/dmg on concinnity). |
| 22 | concinnity AWS auth restoration | Done — (a) `~/.aws/config` manually managed on concinnity (generated by work GitHub workflow); `custom.aws` not enabled. (b) `assumeShellAlias = false` in `granted.nix`; the `assumego` flow now lives in `grassume` (parses output, exports env vars). `assume` / `login` later moved to aws-vault (see row 13). (c) MFA handled inside `op-credential-process`: fetches IAM keys from 1Password, generates TOTP via `ykman`, calls `GetSessionToken`, caches session in 1Password. One YubiKey touch per session; zero credentials on disk. See *Granted + YubiKey setup* below. |
| 23 | Deploy a release or any ref | Done — `just deploy <host> [ref]`: `release` deploys the newest `v*` tag; a tag, branch (freshly fetched `origin/<branch>`) or SHA also works. The recipe checks the ref out detached, deploys, and switches back, also on failure; it refuses to start with uncommitted tracked changes. Every deploy writes `.deploy-status` and records a GitHub Deployment (environment = host, best effort). `just status` shows the host's `configurationRevision` and the latest GitHub deployment per host. See `docs/usage/nix-system.md`. |
| 24 | Bump OIDC role `max_session_duration` 1h → 4h | `push-cache` CI job times out for large closures (~2h build). Fix: set `max_session_duration = 14400` on `aws_iam_role.github_actions` in `terraform/oidc.tf`. |
| 25 | Upgrade nix-homebrew past `postflight_steps` / `--cleanup` regressions | nix-homebrew pinned to `7d0038b` (2026-05-09). Sep 2026 homebrew-cask requires `postflight_steps` (not supported by this version). Latest nix-homebrew (`c11cccf`, 2026-09-20) bundles a Homebrew that removed `--cleanup` from `brew bundle` (used internally by nix-homebrew, no replacement). Workaround: `homebrew-cask` pinned to `dfc9d29` (2026-05-10) and `homebrew-aerospace` to `db2dcd4d` (2026-03-08). When upgrading: find a nix-homebrew that supports `postflight_steps` AND retains `--cleanup`, then remove all three pins. |
| 26 | Claude Code session terminal management | Done — Zellij (`home/modules/zellij.nix`). Use-case layouts: `code` (default: claude · shell · tig · compact bar (session, tabs, mode); `code-resume` = `--resume` picker variant, `zse -l code-resume`), `project` (tabs: master = code shape, agents = full-screen `claude agents`; compact bar via `default_tab_template`), `ticket` (`claude --worktree $ZELLIJ_SESSION_NAME` + shell + tig), `review` (`zse-claude --own --first-prompt "/review:review $ZELLIJ_SESSION_NAME"`: the review runs on the first start only, a restored session resumes; + shell + CI pane, no tig; `zse -l review <PR URL>` names the session `review-<repo>-pr<n>` and starts in `~/github/<owner>/<repo>`), `daily` (claude + the daily-tasks repo's `scripts/tasks-pane` fzf task picker). Every interactive claude pane runs `zse-claude`: `--remote-control` + `--name "$ZELLIJ_SESSION_NAME"`, and with `--own` (code, project, ticket, daily, review) a conversation of its own, keyed by a UUID from session name + start directory (resume if the transcript exists, else `--session-id`); `claude --continue` is not used because it shares the most recent conversation of the directory between sessions. Each pane exports `ZSE_USE_CASE=<use case>` (#110); the `jbl-personal` `project` plugin keys a SessionStart hook off it to inject the master-session ground rules. Env-var substitution lets ticket/review share one layout file across concurrent sessions; no per-session rendering. Fresh `ticket` sessions pre-create the worktree on branch `$ZSE_BRANCH_USER/<id>` (`home/common.nix`). CLI: `zse [-l USE_CASE] [-a AWS_PROFILE] [NAME]` dispatches to the layout, honours `$ZSE_LAYOUT` as a per-repo default, side-cars the AWS profile + expiry at `~/.cache/zse/sessions/<name>.env` and warns on attach when creds are within 15 min of expiry or past; `-a` routes through concinnity's `assume` (`aws-vault exec` 8h with YubiKey TOTP, extended to accept `-- CMD`). Session lifecycle (`zse ls` / `stop` / `kill` / `restore` / `switch`, registry, no resurrection): row 31. Fresh ticket / project / review sessions show a one-time 3-line ASCII banner + hint in the shell pane (sentinel at `~/.cache/zse/sessions/<name>.welcomed` suppresses on resume). zsh completion covers verbs, `-l` and session names. `Ctrl Space` opens the Session Manager picker. The ticket / project / review skills live in `jbl-personal` (a local Claude Code marketplace in `~/github/jbl-taktile/claude-skills`); `gh` and `aws` are excluded from Claude Code's sandbox (`sandbox.excludedCommands`) so `/ticket:start` and friends can reach the GitHub API and AWS. See `docs/usage/zellij.md`. |
| 27 | Enable `tktl-adr-explainer` plugin on concinnity | Pending taktile-org/taktile-skills PR #229, which packages the former `adr-explainer-video` skill as `tktl-adr-explainer` (decks for sprint demo / chapter meetup, optional short / long video, Notion `Status` = Accepted gate). After it merges, add `tktl-adr-explainer@taktile-skills` to `enabledPlugins` in `hosts/concinnity/home.nix` via the existing `jq -s '.[0] * .[1]'` deep-merge. |
| 28 | Configure `jbl-personal` marketplace from Nix (once plugins stable) | Today the `jbl-personal` marketplace (`~/github/jbl-taktile/claude-skills`) and its enabled plugins (`review`, `ticket`, ...) are registered manually in `~/.claude/settings.json`. The home-manager activation in `hosts/concinnity/home.nix` only writes `taktile-skills` + two `tktl-eng-*` plugins (and `sandbox.excludedCommands`); the `jq -s '.[0] * .[1]'` merge preserves whatever is in settings but never *restores* the manual entries if the file is reset, which caused `/review:review` to be unknown after a profile refresh (2026-10-13). Deferred because the plugin set is still churning (ticket / project / review / diagram-builder are being iterated weekly). Once the plugin names + enabled set stabilise, add to `extraKnownMarketplaces` and `enabledPlugins` in the activation: marketplace source `{ source = "directory"; path = "${config.home.homeDirectory}/github/jbl-taktile/claude-skills"; }`, enabled `review@jbl-personal` + `ticket@jbl-personal` (plus any others promoted to daily use). |
| 29 | Remote-friendly SSH auth + commit signing on concinnity | **TODO: sync with IT, Matei and Robin.** The 1Password SSH agent locks with the screen, so git auth + signing fail during remote work (Claude Code Remote Control from the phone) with `failed to fill whole buffer`. Options (1Password kept unlocked, Secretive / Secure Enclave, YubiKey FIDO, split signing key + fine-grained PAT) and trade-offs are in `docs/remote-ssh-auth.md`. Decide after the sync; then implement in `hosts/concinnity/home.nix`. |
| 30 | Proper git pane in Zellij layouts | Done — `zse-git` git pane: `tig status`, or in `ticket` sessions `tig origin/<default>..HEAD` inside `.claude/worktrees/<id>` (waits up to 30 s for the worktree). tig refreshes every 5 s via `~/.config/tig/config` (`refresh-mode periodic`; local `git status`, never a fetch, so no 1Password prompts). `review` layout gets a CI pane (`zse-ci`: `gh pr checks <n>` redrawn every 30 s, HTTPS). `zsek` maps `review-<repo>-pr<n>` to the `.claude/worktrees/pr-<n>` worktree. Panes that wait for Enter after resurrection, and wrong resurrected commands, move to row 31. See `docs/usage/zellij.md`. |
| 31 | zse session registry; no Zellij resurrection | Done — Zellij resurrection saved the *leaf* process of each pane, so a restored session reran `claude … --session-id <id>` (fails: "already in use"), lost `ZSE_USE_CASE` (no plugin rules), used the old saved layout, and started every command pane suspended until Enter (hint hidden by `pane_frames false`). `post_command_discovery_hook` did not rewrite reliably in tests. Now: `session_serialization false`; a registry at `~/.local/state/zse/sessions/<name>` (use case, start dir, AWS profile, timestamps), written by `zse`, removed by `zse kill`; sessions are always (re)created from the current layout, and `zse-claude --own` resumes each session's own conversation. CLI (`home/modules/zse.zsh`): `zse [-l] [-a] NAME` (start/attach; a stopped registered session starts again with its use case and dir; inside Zellij: background start + switch), `zse ls` (running / stopped / orphan / untracked / old-exited), `zse stop [NAME]` (stop, keep entry/worktree/conversation), `zse kill [NAME]` (worktree prompt, cleanup, remove entry, `delete-session --force`), `zse restore [NAME…]` (background start of stopped sessions; `-a` sessions are listed with their command, since `assume` needs the YubiKey), `zse restart --all | NAME…` (stop, then restore — picks up a new layout after a deploy; skips the current session, `--all` skips `-a` sessions), `zse switch NAME` (restore if stopped, then switch); `zsek` / `zss` / `zsep` are deprecated aliases. |

## Hosts

| Host              | OS         | Manager             | Purpose           | Status                   |
|-------------------|------------|----------------------|-------------------|--------------------------|
| serenity          | macOS      | nix-darwin + home-manager | Personal dev     | active                   |
| concinnity        | macOS      | nix-darwin + home-manager | Work dev          | active |
| pi-moodpi         | NixOS      | NixOS + home-manager      | Moodpi service   | planned (config pending) |

More hosts will be added over time.

## Shared Config (home/common.nix)

Tools and config that EVERY host gets:

- Shell: zsh with common aliases (`..`, `l`, `la`, `d1`–`d3`, `wat`, `df`, `rz`, `v`, git shortcuts), `mcd` function, `jj` vi-mode keybinding, cached compinit, build-time completions (just, op)
- Git: personal identity (juliusblank / dev@juliusblank.de), aliases (`co`, `cob`, `st`, `dc`, `ds`, `ba`, `lg`, `bdm`)
- Neovim: treesitter (all grammars), monokai-pro colorscheme, `vim`/`vi` aliased to neovim
- CLI tools: ripgrep, fd, jq, yq, bat, eza, fzf, htop, curl, wget, tree, lazygit
- Terminal multiplexer: Zellij (`home/modules/zellij.nix`) — see roadmap row 26 and `docs/usage/zellij.md`

## Host-Specific Config

- **serenity**: Homebrew casks (GUI apps), personal SSH keys, personal AWS credentials, Firefox (multi-account-containers, open-url-in-container, onepassword-password-manager, granted)
- **concinnity**: Work CLI tools, work SSH keys, work git identity override for repos under `~/github/taktile-org/`, `~/github/jbl-taktile/` (and legacy `~/work/`), company-managed GUI apps (not in nix). See host isolation section below.
- **pi-moodpi**: NixOS system config, moodpi service definition

## Infrastructure

- **OpenTofu** manages: GitHub repo settings, branch protection, PR scope labels, OIDC federation, S3 cache bucket, S3 state bucket, DynamoDB lock table, CI OIDC role + policies, `nix-configs-infra` IAM user + managed policy (switched from Terraform due to BSL 1.1 license)
- **S3 backend** for OpenTofu state (versioned, locked via DynamoDB) — bucket and table are themselves managed by tofu; bootstrap with `just setup-terraform-backend` then `just tf-import-backend`
- **GitHub Actions** for CI: path-aware jobs (`dorny/paths-filter`) — `check-flake` (macos-14, `nix flake check` + parallel matrix build of serenity and concinnity) only runs when nix files change; `validate-release` runs on release branches; `ci-passed` fan-in is the single required status check; `push-cache` matrix pushes both host closures to S3 on same-repo PRs and on merge to main (see [docs/ci.md](ci.md))
- **PR scope labels** (`infra`, `ci`, `host:serenity`, `host:concinnity`, `home`, `flake`, `deps`, `docs`) are applied by `.github/workflows/pr-labeler.yml` based on file paths in `.github/labeler.yml`. Labels themselves are declared in `terraform/github-labels.tf` so they stay in sync with the mapping file.
- **S3 binary cache** for nix store paths (signed, used by all hosts + CI) — active; serenity configured with **`nix.settings`** substituters and trusted public key; CI pushes closures on every PR CI run (same-repo) and on every merge to main, so paths introduced by a PR are warm before the merge build


### Nix cache activation

Complete. The S3 cache bucket is public-read. The signing key pair was generated via
`just setup-nix-cache-keys`; the private key is in 1Password (`op://github_nix-configs/Nix Cache
Signing Key/private_key`) and the public key is committed in `hosts/serenity/configuration.nix`.
The `push-cache` CI job (`macos-14` runner) is a matrix over both hosts (serenity, concinnity)
that pushes each closure to S3 in parallel, using the signing key read from 1Password at runtime
via the `github-actions-nix-configs` service account. It runs on every same-repo PR CI run **and**
on every merge to main, so a derivation introduced by a PR (e.g. a nixpkgs bump that invalidates
a hash) lands in the cache during the PR build itself — the next CI run on that PR, and the final
merge-to-main run, both skip the rebuild. Concinnity was added to `push-cache` so its host-specific
paths (aws-vault override, granted, ykman, the op-credential-process wrapper) are warm for the next
PR build instead of cold-built every time. Fork PRs are excluded (no OIDC / secrets access).

**Retention / cost control.** `terraform/s3-cache.tf` sets a lifecycle policy on the bucket:
current objects expire after 90 days, non-current versions (from the versioning config) after 30.
Store paths are content-addressed, so paths still referenced by a current host closure get
re-uploaded on each push-cache run and stay warm; paths orphaned by an abandoned PR or a flake
input bump age out automatically. Tune the `expiration.days` value if cost grows faster than
expected after push-cache started running on PR builds.

## Secrets Management

- **1Password** is the single password manager across all machines — no secrets stored in the repo
- **1Password CLI (`op`)** injects secrets via `op read "op://..."`: AWS and GitHub credentials at shell entry in `shell.nix` shellHook; tofu-specific tokens (`TF_VAR_*`) per-recipe in the justfile
- **1Password SSH agent** serves SSH keys to all SSH connections via `IdentityAgent` in `~/.ssh/config`
- `op` (1Password CLI) installed via nix (`_1password-cli` in `home/darwin.nix`); the 1Password app via Homebrew cask on serenity and company distribution (IRU) on concinnity
- `~/.ssh/config` managed by home-manager; configures `IdentityAgent` to the 1Password socket

### Vault & item conventions

Infrastructure secrets are split across two vaults:

| Secret | Vault | Item name | Field(s) |
|---|---|---|---|
| AWS IAM access keys | `infrastructure` | `personal-nix-configs-infra` | `access_key_id`, `secret_access_key` |
| 1Password SA token (CI) | `infrastructure` | `github-actions-nix-configs` | `token` |
| GitHub PAT | `github_nix-configs` | `GitHub PAT nix-configs` | `token` |
| Nix cache signing key | `github_nix-configs` | `Nix Cache Signing Key` | `private_key`, `public_key` |

Secret reference format: `op://<vault>/<item name>/<field name>`

### Injecting secrets in scripts

`shell.nix` shellHook injects the GitHub PAT and default AWS profile **only when
`hostname -s` is `serenity`** (and not in CI), via `op read`. That keeps personal-infra
tokens off concinnity and other machines where those vault items are absent or must
not be used.

Tofu-specific tokens (`TF_VAR_*`) are injected per-recipe in the justfile:

```bash
TF_VAR_github_token=$(op read "op://github_nix-configs/GitHub PAT nix-configs/token")
TF_VAR_op_service_account_token=$(op read "op://infrastructure/github-actions-nix-configs/token")
export TF_VAR_github_token TF_VAR_op_service_account_token
```

The `.op-env` file at the repo root documents all required secrets as `op://` references.

## AWS Isolation

- `~/.aws/config` managed declaratively by `home/modules/aws.nix` on serenity; manually managed on concinnity (generated by the taktile-infra workflow); never contains secrets
- Credentials sourced via `credential_process` (1Password locally, OIDC env vars in CI)
- On **serenity** only, `shell.nix` sets `AWS_CONFIG_FILE`, `AWS_PROFILE=personal-nix-configs-infra`,
  and `AWS_DEFAULT_REGION` for working in this repo; **concinnity** uses its manually
  managed `~/.aws/config` without those devShell defaults (`custom.aws` is not enabled there)
- OIDC role for GitHub Actions (`nix-configs-github-actions`) is scoped to this repo only

### IAM Identity Center & multi-account setup (in progress)

> Current setup uses IAM access keys alongside Granted for role switching.

Goal: migrate to **AWS IAM Identity Center (SSO)** for a multi-account-ready credential setup.

- **Granted** installed via Homebrew on serenity and nix `home.packages` on concinnity; reusable module at `home/modules/granted.nix`
- Firefox managed by home-manager via NUR on both hosts: **Multi-Account Containers** + **open-url-in-container** + **Granted addon** for isolated AWS console sessions; serenity additionally has **1Password** extension
- Next steps: configure SSO profiles in `~/.aws/config`

### Granted + YubiKey setup (concinnity)

**Shell command** (declared in `hosts/concinnity/home.nix`):

`assume <profile> [-- CMD]` — `aws-vault exec` (8h; 2h for `*on-call-engineer-write*`),
1Password desktop backend, `ykman` as MFA prompt. `login <profile>` — console in a Firefox
container via `aws-vault login`. `grassume <profile>` — calls `assumego` directly (not the
granted shell wrapper), parses output and exports env vars; used for profiles that use
`op-credential-process` (below). All three tab-complete profile names.

**Credential flow** (all handled by `op-credential-process`, a nix-managed wrapper script):

1. Fetches IAM access keys from 1Password via `op read`
2. Generates TOTP from YubiKey via `ykman oath accounts code`
3. Calls `aws sts get-session-token` with MFA
4. Caches the session credentials as a 1Password item (`session-<item-name>` in the same vault)
5. Returns `credential_process` JSON to the AWS SDK

One YubiKey touch per session (typically 12h); subsequent role assumptions use the cached session.
Zero credentials on disk — IAM keys and session cache both live in 1Password.

**`~/.aws/config` setup:**

Base profiles use `op-credential-process` with the 1Password item path and MFA ARN.
Role profiles use `source_profile` only — no `mfa_serial` needed (the base session already
carries the MFA assertion from `GetSessionToken`).

```ini
[profile tktliam]
region             = eu-central-1
credential_process = op-credential-process op://aws-vault/granted-tktliam arn:aws:iam::685159096301:mfa/julius.blankyubikey

[profile some-account.core-engineer]
source_profile = tktliam
region         = eu-central-1
role_arn       = arn:aws:iam::<account-id>:role/tktl-core-engineer
```

**1Password item requirements:** The base item (e.g. `granted-tktliam` in vault `aws-vault`)
must have fields `access_key_id` and `secret_access_key`. The session cache item
(`session-granted-tktliam`) is created/updated automatically by `op-credential-process`.

## Git Identity Isolation

- **Default identity** (Julius Blank / dev@juliusblank.de) comes from `home/common.nix`
  for every host. `signing.signByDefault = true` is set there too; the signing **key**
  is declared per-host (see below) so each machine signs with the pubkey whose private
  counterpart its local 1Password agent actually serves.
- **Per-host signing key:**
  - **serenity** signs with the personal SSH key served by the host's 1Password agent
    (`hosts/serenity/home.nix` sets `programs.git.signing.key`).
  - **concinnity** signs with a **dedicated personal signing key** served from the
    host's 1Password (`concinnity signing key` item, Employee vault) and registered
    as a signing key on juliusblank's GitHub account. This key is scoped to this host,
    so no personal 1Password account is required on the work laptop. GitHub binds any
    pubkey to exactly one account; the work key is already registered under the
    taktile-org identity, so it cannot double as a signing key for personal commits.
  - `home/common.nix` lists all three personal pubkeys in `personalAllowedSigners`,
    all tagged `dev@juliusblank.de`, so `git log --show-signature` verifies commits
    as me regardless of which host signed them. The work pubkey is **not** listed
    here — it signs only commits under the work `includeIf` paths on concinnity,
    verified via `custom.extraAllowedSigners` as `julius.blank@taktile.com`.
- **concinnity:** `programs.git.includes` in `hosts/concinnity/home.nix` applies work
  name, email, **and the work signing key** when `gitdir` matches
  `~/github/taktile-org/` (canonical for all work org clones) or `~/github/jbl-taktile/`
  (personal work-account repos, e.g. the `jbl-personal` Claude marketplace and
  daily-tasks; they push to the work GitHub account). `gitdir:~/work/` is
  still included for legacy checkouts until they are moved. Everything outside those
  paths signs with the concinnity personal signing key from the top-level default.
- **serenity:** no work `includeIf` on that machine.
- **Stray `~/.gitconfig` shadow.** Git reads both `~/.gitconfig` and
  `~/.config/git/config`, with the former winning on conflicting keys. 1Password
  onboarding and some work MDM setups write a `~/.gitconfig` that pins work
  identity, signing key, and cert overrides — silently shadowing home-manager and
  authoring every commit as the work identity, even in personal repos. `home/darwin.nix`
  removes the file on every activation; `gpg.ssh.program` (op-ssh-sign) is set in
  the same module so 1Password-backed SSH signing survives the removal. Aikido's
  cert bundle path (concinnity-only) is preserved via `programs.git.settings.http.sslCAInfo`
  in `hosts/concinnity/home.nix`.

### GitHub checkout layout (`~/github/` on concinnity)

| Directory | Purpose |
|---|---|
| `~/github/juliusblank/` | Personal GitHub account — **`nix-configs` must live here** (`~/github/juliusblank/nix-configs` on every macOS host) |
| `~/github/taktile-org/` | Work org (`taktile`) — all work repos; work git identity applies |

Keeping `nix-configs` under `juliusblank` (not inside `taktile-org/`) ensures this
repo never matches the work `includeIf` rules.

### Canonical clone path for `nix-configs` (macOS)

**Both serenity and concinnity:** `~/github/juliusblank/nix-configs`

Use this path in docs, scripts, and muscle memory on every macOS host so `flake`
URLs and examples stay consistent.

Nothing in nix-darwin/home-manager embeds the clone path; only commands you run do
(e.g. **`just deploy serenity`** from **`~/github/juliusblank/nix-configs`**, or a manual
**`sudo "$(nix build --no-link --print-out-paths …#darwin-rebuild)/bin/darwin-rebuild" switch --flake …`**
with the same flake path and nix-darwin pin as **`flake.nix`** / **`justfile`** — see
**`docs/usage/nix-system.md`**).

## Serenity and concinnity isolation

**Goal:** share nix modules and tooling while keeping **work credentials and access
patterns off the personal machine** and avoiding **personal-infra secrets on the work
machine** unless explicitly intended (e.g. SSH read access to selected personal repos).

| Concern | serenity | concinnity |
|---|---|---|
| Canonical `nix-configs` clone path | `~/github/juliusblank/nix-configs` | same (must **not** live under `~/github/taktile-org/`) |
| `shell.nix` `GH_TOKEN` / `AWS_PROFILE` for this repo | Injected when hostname is `serenity` | Not set by shellHook — no `op read` to personal-infra or `github_nix-configs` PAT for routine shell |
| Nix binary cache substituters | Enabled (see `hosts/serenity/configuration.nix`) | **Disabled** — avoid pulling personal closures onto a work-managed device |
| 1Password SSH agent (`~/.config/1password/ssh/agent.toml`) | Declared in `hosts/serenity/home.nix` (Private vault keys + Claude key item) | Declared in `hosts/concinnity/home.nix` — minimal key set (e.g. work GitHub key + chosen personal key for cross-use repos); omit keys for domains that must stay off work |
| Homebrew GUI apps | Declarative casks in nix-homebrew | **None in nix** — company distribution (IRU); brews only where needed. The Claude *desktop app* (chat GUI) is IRU-managed; `claude-code` (the CLI dev tool) is a separate product and is nix-managed on both hosts. |
| AWS profiles | `custom.aws` + 1Password `credential_process` for personal infra | Manually managed `~/.aws/config` (generated by the taktile-infra workflow); `custom.aws` not enabled |
| Claude Code plugins | None declared | `taktile-skills` marketplace + `tktl-eng-data`, `tktl-eng-frontend` — plus `sandbox.excludedCommands = [ "gh" "aws" ]` — deep-merged into `~/.claude/settings.json` by a `home.activation` step in `hosts/concinnity/home.nix` (file stays writable) |
| YubiKey + AWS | As needed | **`yubikey-manager`** (CLI **`ykman`**): MFA prompt for aws-vault (`assume` / `login`) and TOTP inside **`op-credential-process`** (`grassume` → `assumego`); all in **`hosts/concinnity/home.nix`** |

**Work project devShells:** live in a **separate flake repo** on the work GitHub account.
Each work repo uses `direnv` + `use flake …` pointing at that flake (`nix-direnv` is in
`home/common.nix`). This repo only provides the shared user environment that makes
that pattern work — not the work-specific package sets.

Once those work devShells are in place, **concinnity** can uninstall redundant Homebrew
CLIs that duplicate devShell or nix coverage: `mise`, `pyenv`, `pipx`, `prek` (pre-commit
via project shells), `tfenv`, `mkcert`, `lsd`. Brew **Python@** formulae may remain until
unused. **Neovim** is provided via `programs.neovim` in `home/common.nix` (placeholder
`init.lua` — extend in-repo when ready).

Everything else that still appears under `brew list --formula` (e.g. `autoconf`, `gettext`,
`luajit`, `openssl@3`, `cffi`, `sqlite`, `grep` as a brew duplicate of GNU grep, Neovim
build deps) is treated as **transitive** — **do not** add those formulae to this flake;
uninstall migrated **leaves** first (`brew leaves`), then **`brew autoremove`** to peel
orphaned deps.

## Claude Configuration

- `CLAUDE.md` at the repo root: conventions, nix style guide, commit style, and repo-specific instructions for Claude Code sessions
- Claude Code settings committed to the repo so every session on any machine starts with the same context
- **Cursor:** `.cursor/rules/nix-configs.mdc` (`alwaysApply: true`) instructs agents to read `docs/SPEC.md` and follow `CLAUDE.md` so editor-based sessions match the same rules without duplicating long policy
- Goal: eliminate the manual onboarding that happens at the start of each session
- Conventions enforced via `CLAUDE.md`: spec-first workflow, conventional commits, always format after nix edits, safety rules around deployment

## Changelog

- **`CHANGELOG.md`** generated from conventional commit messages using `git-cliff`
- Regenerated only at release time by `.github/workflows/release.yml` (via
  `orhun/git-cliff-action`); the per-commit pre-commit regen was removed because
  it caused merge conflicts on every PR without adding information — `git log`
  already carries the record `git-cliff` reads from
- `git-cliff` is still available in the devShell; run `just changelog` to preview
  or regenerate manually when needed
- Config lives in `cliff.toml` at the repo root

### Versioning & tagging

This repo uses **CalVer** (`v<year>.<month>.<n>`, e.g. `v2026.04.1`) rather than SemVer. SemVer's
breaking/feature/patch semantics don't map onto personal system configuration — CalVer reflects
that the cadence is time-driven, not API-driven.

- Tag after meaningful milestones (roadmap item shipped, major config overhaul, etc.) — not on every merge
- **Canonical path:** trigger `.github/workflows/release.yml` via `workflow_dispatch` in the GitHub UI
  — it always starts at `.1` and increments (`v2026.04.1` → `v2026.04.2` → ...), creates the tag,
  re-sections `CHANGELOG.md` under the new tag, and opens a PR; merge via the GitHub UI to publish
- git-cliff sections the changelog by tag automatically; untagged commits appear under **Unreleased**

## Code Conventions

### Formatting

- **Indentation**: spaces only — use the count that matches the language's best practice (see table below)
- **Line length**: 100 characters maximum
- **Trailing whitespace**: never
- **File endings**: every file ends with a single newline

Where a dedicated formatter exists, it is the authority on style:

| Language | Formatter | Linter | Indentation |
|---|---|---|---|
| Nix | `nixfmt-rfc-style` (`just fmt`) | `statix` (`just lint`) | 2 spaces |
| HCL | `tofu fmt` | — | 2 spaces |
| YAML | — (manual) | — | 2 spaces |
| Shell | — (manual) | — | 2 spaces |

**Nix linting with statix:** `statix check` catches anti-patterns the formatter cannot fix — shadowed `with` scopes, useless `let … in`, redundant `inherit`, empty `let` blocks, and similar. Run `just lint` to check, `just lint-fix` to auto-remediate. The pre-commit hook runs statix on staged `.nix` files and blocks the commit if findings are present.

### Doc comments

All public-facing definitions must carry a doc comment sufficient for auto-completion discovery.
Describe *what* the thing is and any non-obvious constraints; omit comments that just restate the name.

| Language | Style |
|---|---|
| Nix | `/**` block comment immediately before the definition (nixdoc-compatible) |
| HCL | `#` description block before each `resource`, `variable`, `output`, or `module` |
| Shell | `#` comment block directly above the function |
| YAML | Top-level `#` comment on each workflow file; inline `#` on non-obvious steps |

### Language isolation

Each language or framework used in this repo lives in a dedicated subdirectory and is accompanied
by a `CLAUDE.md` scoped to that directory containing language-specific conventions.
The root `CLAUDE.md` covers Nix, which is the primary language of the repo.

| Directory | Language / Framework |
|---|---|
| `terraform/` | HCL (OpenTofu) |
| `.github/` | YAML (GitHub Actions) |

## Development Workflow

1. Update `docs/SPEC.md` with desired changes
2. Use AI assistant (Claude) with spec as context to generate nix config
3. Test locally: `just check` or `just build <host>`
4. Open a PR — CI validates (`ci-passed` required status check)
5. Merge via GitHub UI (squash merge) — branch is auto-deleted
6. Deploy: `just deploy <host>`

PRs are squash-merged to keep a clean commit history on `main`. No review required (solo repo). `CHANGELOG.md` is regenerated only at release time (see *Changelog* above).

## Pre-commit Hooks

Installed automatically when entering the devShell (`nix develop`):

- **nixfmt** — formats all staged `.nix` files and re-stages them
- **statix** — lints all staged `.nix` files after nixfmt; blocks the commit if any findings are present (run `just lint-fix` to auto-remediate)
- **tofu fmt** — formats all staged `.tf` files and re-stages them
- **flake.lock check** — errors if `flake.nix` is staged but `flake.lock` has unstaged changes (catches forgotten `nix flake lock` runs)

## Backup

> **Planned.**

Reliable, simple backup of serenity user data to AWS S3.

**Data categories:** music collection, photos, projects (and any other user data identified over time)

**Principles:**
- Simple enough to run quickly — "just do it" with a single command
- A backup is only as good as its restore — restore verification is a first-class requirement, not an afterthought
- S3 as the storage backend (consistent with existing AWS setup)
- Extensible to other hosts over time

**Open questions:** tool selection (restic, rclone, etc.), restore test strategy (automated schedule vs. on-demand structured process), S3 bucket layout and lifecycle policy.

## Project Conventions & Structure

> **Planned — ongoing improvement.**

Continuously improve the structure of the spec, Claude configuration, and project conventions to maximise efficiency of both developer time and AI resources.

**Scope:**
- Well-structured, navigable spec that serves as reliable AI context
- Scoped conventions per directory/topic (e.g. IaC-specific rules in `terraform/`, nix module conventions for `hosts/` and `home/`)
- `CLAUDE.md` structured to give Claude precise, relevant context without noise
- Nix module organisation conventions (when to split modules, naming, structure)

This is treated as an ongoing process rather than a one-time task — conventions are added and refined as the project grows.

## Tool Setup & Dotfiles

> **Planned — to be done step by step with AI assistance.**

Consolidate fine-tuned system and shell configuration from old personal repos into this repo.

**Source:** two or three existing repos containing configurations built up over time, primarily on Linux.

**Categories (non-exhaustive):** starship prompt, zsh setup, vim config, and other CLI tool configurations.

**Approach:**
1. Share old repos in a Claude session
2. Claude analyses the content and asks what to keep
3. Integrate selected config into `home/common.nix` (cross-platform) or platform-specific modules
4. Linux-specific config goes into NixOS host modules; macOS-compatible config into `home/darwin.nix` or `home/common.nix`

## DJ Toolchain

> **Planned.**

Rekordbox and DJ workflow automation lives in this repo — it is part of the personal toolchain, no different from developer or admin tool setup.

**Rekordbox automation & process improvement:**
- Streamline DJ workflow (library management, preparation, export)
- Automation scripts for recurring tasks
- Integration with existing system setup (e.g. file paths, backup)

**Rekordbox MCP server:**
> Exploratory. Project home and scope TBD pending broader decision on project organisation.

- Experiment with an MCP server interface to rekordbox data/functionality
- Relevant to AI-assisted DJ workflow tooling
