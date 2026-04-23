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
| 3 | GitHub Actions CI workflow (`nix flake check`) | Done — path-aware jobs via `dorny/paths-filter`; `check-flake` (macos-14) only runs when nix files change; `validate-release` runs on `chore/release-*` branches; `ci-passed` fan-in is the single required status check; `push-cache` pushes the serenity closure to S3 on merge to main |
| 4 | `tf-apply` guardrails | Done — hard block if not on `main` and working tree is dirty; soft warn (warn + require Enter) if not on `main` but tree is clean; on `main`, runs without interruption. `tf-plan` prints a warning when not on `main`. CI bypasses naturally (always clean, always on main). |
| 5 | `tf-plan` / `tf-apply` plan-to-file workflow | Done — `tf-plan` saves `tofu plan -out=tfplan`; `tf-apply` requires the plan file, runs `tofu apply tfplan`, then deletes it. Apply is deterministic (no re-evaluation). `tf-apply` exits with an error if no plan file exists. |
| 6 | Automated CI/CD for infrastructure | Done — `.github/workflows/infra.yml` triggers on `terraform/**` changes. On PR: fresh `tofu plan`, output posted as a PR comment (collapsed, truncated at 60 KB). On merge to `main`: fresh plan + apply in one job. AWS via OIDC; GitHub provider token fetched live from 1Password via `1password/load-secrets-action` on every run (SA: `github-actions-nix-configs`, vault: `github_nix-configs`). OIDC role extended with three scoped policies: tofu state backend (S3 + DynamoDB), IAM resource management, and nix cache bucket config. `OP_SERVICE_ACCOUNT_TOKEN` secret managed by terraform; SA token stored at `op://Private/1Password SA github-actions-nix-configs/token`. |
| 7 | Infrastructure tests | Validate OpenTofu modules with automated tests (candidate: Terratest or `tofu test`). Cover at minimum: S3 bucket exists and is private, IAM role trust policy is correctly scoped, OIDC provider URL is correct. Depends on #6. |
| 8 | Nix cache activation | Done — S3 bucket configured public-read; CI `push-cache` job wired (macos-14, pushes on merge to main); signing key generated and stored in 1Password; public key filled into `hosts/serenity/configuration.nix` with substituters uncommented; serenity deployed with cache config active; cache seeded via CI on each merge to main. |
| 9 | Changelog via `git-cliff` | Done — `cliff.toml` at repo root; pre-commit hook regenerates `CHANGELOG.md` on every commit; `release.yml` workflow_dispatch creates CalVer tag (`v<year>.<month>.<n>`) and opens a release PR with re-sectioned changelog |
| 10 | Backup — serenity user data to S3 | Music, photos, projects; restore verification required |
| 11 | `macbook-work` host config | Includes editor + tmux config in `home/common.nix` |
| 12 | AWS IAM Identity Center migration | In progress — Granted adopted for local AWS access. `granted` and `aws-vault` installed via homebrew brews. `awscli2` system-wide via `home/darwin.nix`. Granted module at `home/modules/granted.nix` (`custom.granted.enable`). Firefox managed by home-manager with Multi-Account Containers + Granted extensions via NUR. macOS keychain for credential storage (granted default). Next: configure SSO profiles and migrate `credential_process` from 1Password static keys to Granted SSO once IAM Identity Center is set up. |
| 13 | AWS CLI credential management | Done — `awscli2` system-wide via `home/darwin.nix`. `~/.aws/config` managed by `home/modules/aws.nix` (`custom.aws.enable`); written as a writable copy on each activation. Profile naming convention: `<org>_<account>_<user>`. `jbl_root_root` profile on serenity uses `credential_process` backed by 1Password (`op://Private/aws_root/`); `tktliam` is a placeholder on macbook-work. devShell uses `AWS_CONFIG_FILE=$HOME/.aws/config`, `AWS_PROFILE=jbl_root_root`; CI overrides via `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` env vars (OIDC). `assume` alias in `~/.zshenv` for Granted SSO workflow. |
| 14 | Tool setup & dotfiles consolidation | Review old repos step by step |
| 15 | DJ toolchain — rekordbox automation | Process improvements, scripts |
| 16 | Rekordbox MCP server | Scope and project home TBD |
| 17 | `pi-moodpi` host config | Lower urgency |
| 18 | nixpkgs upgrade to 25.11 | Done — bumped `nixpkgs` to `nixpkgs-25.11-darwin`, `nix-darwin` to `nix-darwin-25.11`, `home-manager` to `release-25.11`. Enables declarative Firefox extensions on macOS (home-manager PR #6913). nix-homebrew pin kept (brew 5.0.12, ruby_3_4 compat). Next upgrade: 26.05 (end of May 2026); drop the nix-homebrew pin then; retry `git-hooks.nix` / `pre-commit-hooks.nix`. |
| 19 | Terraform state bucket + DynamoDB under tofu management | Done — `terraform/state-backend.tf` defines both resources; `just tf-import-backend` imports them after initial bootstrap; `setup-terraform-backend` now prompts to run the import step |

## Hosts

| Host              | OS         | Manager             | Purpose           | Status                   |
|-------------------|------------|----------------------|-------------------|--------------------------|
| serenity          | macOS      | nix-darwin + home-manager | Personal dev     | active                   |
| macbook-work      | macOS      | nix-darwin + home-manager | Work dev          | planned (not deployed)   |
| pi-moodpi         | NixOS      | NixOS + home-manager      | Moodpi service   | planned (config pending) |

More hosts will be added over time.

## Shared Config (home/common.nix)

Tools and config that EVERY host gets:

- Shell: zsh with common aliases and functions
- Git: personal identity (juliusblank / dev@juliusblank.de)
- Editor config (TBD)
- CLI tools: ripgrep, fd, jq, yq, bat, eza, fzf, htop, curl, wget, tree
- tmux / terminal multiplexer config (TBD)

## Host-Specific Config

- **serenity**: Homebrew casks (GUI apps), personal SSH keys
- **macbook-work**: Work-specific tools, work SSH keys, work git identity override for work repos
- **pi-moodpi**: NixOS system config, moodpi service definition

## Infrastructure

- **OpenTofu** manages: GitHub repo settings, branch protection, OIDC federation, S3 cache bucket, S3 state bucket, DynamoDB lock table, CI OIDC role + policies, `nix-configs-infra` IAM user + managed policy (switched from Terraform due to BSL 1.1 license)
- **S3 backend** for OpenTofu state (versioned, locked via DynamoDB) — bucket and table are themselves managed by tofu; bootstrap with `just setup-terraform-backend` then `just tf-import-backend`
- **GitHub Actions** for CI: path-aware jobs (`dorny/paths-filter`) — `check-flake` (macos-14, `nix flake check` + serenity build) only runs when nix files change; `validate-release` runs on release branches; `ci-passed` fan-in is the single required status check; `push-cache` pushes the serenity closure to S3 on merge to main (see [docs/ci.md](ci.md))
- **S3 binary cache** for nix store paths (signed, used by all hosts + CI) — active; serenity configured with substituters and trusted public key; CI pushes closure on every merge to main


### Nix cache activation

Complete. The S3 cache bucket is public-read. The signing key pair was generated via
`just setup-nix-cache-keys`; the private key is in 1Password (`op://github_nix-configs/Nix Cache
Signing Key/private_key`) and the public key is committed in `hosts/serenity/configuration.nix`.
The `push-cache` CI job (`macos-14` runner) pushes the serenity closure to S3 on every merge to
main using the signing key read from 1Password at runtime via the `github-actions-nix-configs`
service account.

## Secrets Management

- **1Password** is the single password manager across all machines — no secrets stored in the repo
- **1Password CLI (`op`)** injects secrets via `op read "op://..."`: AWS and GitHub credentials at shell entry in `shell.nix` shellHook; tofu-specific tokens (`TF_VAR_*`) per-recipe in the justfile
- **1Password SSH agent** serves SSH keys to all SSH connections via `IdentityAgent` in `~/.ssh/config`
- `1password` (app) and `1password-cli` installed via Homebrew on all macOS hosts
- `~/.ssh/config` managed by home-manager; configures `IdentityAgent` to the 1Password socket

### Vault & item conventions

Infrastructure secrets are split across two vaults:

| Secret | Vault | Item name | Field(s) |
|---|---|---|---|
| AWS IAM access keys | `Private` | `aws_root` | `access_key_id`, `secret_access_key` |
| 1Password SA token (CI) | `Private` | `1Password SA github-actions-nix-configs` | `token` |
| GitHub PAT | `github_nix-configs` | `GitHub PAT nix-configs` | `token` |
| Nix cache signing key | `github_nix-configs` | `Nix Cache Signing Key` | `private_key`, `public_key` |

Secret reference format: `op://<vault>/<item name>/<field name>`

### Injecting secrets in scripts

AWS and GitHub credentials are injected once at devShell entry via `shell.nix` shellHook.
Tofu-specific tokens are injected per-recipe in the justfile:

```bash
TF_VAR_github_token=$(op read "op://github_nix-configs/GitHub PAT nix-configs/token")
TF_VAR_op_service_account_token=$(op read "op://Private/1Password SA github-actions-nix-configs/token")
export TF_VAR_github_token TF_VAR_op_service_account_token
```

The `.op-env` file at the repo root documents all required secrets as `op://` references.

## AWS Isolation

- `~/.aws/config` managed declaratively by `home/modules/aws.nix`; never contains secrets
- Credentials sourced via `credential_process` (1Password locally, OIDC env vars in CI)
- devShell sets `AWS_CONFIG_FILE=$HOME/.aws/config`, `AWS_PROFILE=jbl_root_root`, `AWS_DEFAULT_REGION=eu-central-1`
- OIDC role for GitHub Actions (`nix-configs-github-actions`) is scoped to this repo only

### IAM Identity Center & multi-account setup (in progress)

> Current setup uses IAM access keys (stored in 1Password) alongside Granted for SSO.

Goal: migrate to **AWS IAM Identity Center (SSO)** for a multi-account-ready credential setup.

- **Granted** adopted — installed via homebrew (`granted` + `aws-vault`); reusable module at `home/modules/granted.nix`
- `assume` alias configured in zsh — sources credentials into the current shell
- Firefox managed by home-manager with **Multi-Account Containers** + **Granted addon** for isolated AWS console sessions
- Credential storage: macOS keychain (granted default)
- **aws-vault** preserved for backward compatibility
- Next steps: configure SSO profiles in `~/.aws/config`, then remove IAM access keys from 1Password and update `shell.nix` shellHook

## Git Identity Isolation

- Repo-level `.gitconfig` enforces personal identity (Julius Blank / dev@juliusblank.de)
- Work machine uses `includeIf gitdir:~/work/` to override identity for work repos
- This repo lives under `~/personal/` and always uses the personal identity

## Claude Configuration

- `CLAUDE.md` at the repo root: conventions, nix style guide, commit style, and repo-specific instructions for Claude Code sessions
- Claude Code settings committed to the repo so every session on any machine starts with the same context
- Goal: eliminate the manual onboarding that happens at the start of each session
- Conventions enforced via `CLAUDE.md`: spec-first workflow, conventional commits, always format after nix edits, safety rules around deployment

## Changelog

- **`CHANGELOG.md`** generated from conventional commit messages using `git-cliff`
- Updated automatically by the pre-commit hook on every commit (inside the devShell)
- `git-cliff` is available in the devShell; run `just changelog` to regenerate manually
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

| Language | Formatter | Indentation |
|---|---|---|
| Nix | `nixfmt-rfc-style` (`just fmt`) | 2 spaces |
| HCL | `tofu fmt` | 2 spaces |
| YAML | — (manual) | 2 spaces |
| Shell | — (manual) | 2 spaces |

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

PRs are squash-merged to keep a clean commit history on `main`. No review required (solo repo). `CHANGELOG.md` is updated by the pre-commit hook on every commit.

## Pre-commit Hooks

Installed automatically when entering the devShell (`nix develop`):

- **nixfmt** — formats all staged `.nix` files and re-stages them
- **tofu fmt** — formats all staged `.tf` files and re-stages them
- **flake.lock check** — errors if `flake.nix` is staged but `flake.lock` has unstaged changes (catches forgotten `nix flake lock` runs)
- **git-cliff** — regenerates `CHANGELOG.md` (Unreleased section) and re-stages it on every commit; only runs inside the devShell where `git-cliff` is available

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
