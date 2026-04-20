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
| 3 | GitHub Actions CI workflow (`nix flake check`) | Done — `nix_path` removed (flake-only, no legacy `<nixpkgs>` needed); `check-flake` moved to `macos-14` so serenity builds for real (not `--dry-run`) on every PR and push to main |
| 4 | `tf-apply` guardrails | Done — hard block if not on `main` and working tree is dirty; soft warn (warn + require Enter) if not on `main` but tree is clean; on `main`, runs without interruption. `tf-plan` prints a warning when not on `main`. CI bypasses naturally (always clean, always on main). |
| 5 | `tf-plan` / `tf-apply` plan-to-file workflow | Done — `tf-plan` saves `tofu plan -out=tfplan`; `tf-apply` requires the plan file, runs `tofu apply tfplan`, then deletes it. Apply is deterministic (no re-evaluation). `tf-apply` exits with an error if no plan file exists. |
| 6 | Automated CI/CD for infrastructure | Done — `.github/workflows/infra.yml` triggers on `terraform/**` changes. On PR: fresh `tofu plan`, output posted as a PR comment (collapsed, truncated at 60 KB). On merge to `main`: fresh plan + apply in one job. AWS via OIDC; GitHub provider token fetched live from 1Password via `1password/load-secrets-action` on every run (SA: `github-actions-nix-configs`, vault: `github_nix-configs`). OIDC role extended with three scoped policies: tofu state backend (S3 + DynamoDB), IAM resource management, and nix cache bucket config. `OP_SERVICE_ACCOUNT_TOKEN` secret managed by terraform; SA token stored at `op://Private/1Password SA github-actions-nix-configs/token`. |
| 7 | Infrastructure tests | Validate OpenTofu modules with automated tests (candidate: Terratest or `tofu test`). Cover at minimum: S3 bucket exists and is private, IAM role trust policy is correctly scoped, OIDC provider URL is correct. Depends on #6. |
| 8 | Nix cache activation | Done — S3 bucket configured public-read; CI `push-cache` job wired (macos-14, pushes on merge to main); signing key generated and stored in 1Password; public key filled into `hosts/serenity/configuration.nix` with substituters uncommented; serenity deployed with cache config active; cache seeded via CI on each merge to main. |
| 9 | Changelog via `git-cliff` | Depends on CI |
| 10 | Backup — serenity user data to S3 | Music, photos, projects; restore verification required |
| 11 | `macbook-work` host config | Includes editor + tmux config in `home/common.nix` |
| 12 | AWS IAM Identity Center migration | Granted vs 1Password, multi-account |
| 13 | AWS CLI credential management | Decide on auth approach (profiles, Identity Center, Granted) and implement consistently: devShell injection, justfile recipes, nix-managed config. Currently inconsistent — AWS creds injected per justfile recipe via `op read`, GitHub token injected in devShell. Depends on #12. |
| 14 | Tool setup & dotfiles consolidation | Review old repos step by step |
| 15 | DJ toolchain — rekordbox automation | Process improvements, scripts |
| 16 | Rekordbox MCP server | Scope and project home TBD |
| 17 | `pi-moodpi` host config | Lower urgency |
| 18 | nixpkgs upgrade to 26.05 | Scheduled for end of May 2026 when 26.05 releases. Steps: bump `nixpkgs` and `nix-darwin` URLs to `nixpkgs-26.05-darwin` / `nix-darwin-26.05`; drop the nix-homebrew pin (see comment in `flake.nix`); retry `git-hooks.nix` / `pre-commit-hooks.nix` (blocked by missing `cspell` in 25.05). Branch `docs/spec-audit-nixpkgs-2605` reserved for this work. |
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
- **GitHub Actions** for CI: `nix flake check` + real serenity build on every PR and push to main (macos-14); cache push on merge to main
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
- **1Password CLI (`op`)** injects secrets at runtime via `op read "op://..."` in justfile recipes
- **1Password SSH agent** serves SSH keys to all SSH connections via `IdentityAgent` in `~/.ssh/config`
- `1password` (app) and `1password-cli` installed via Homebrew on all macOS hosts
- `~/.ssh/config` managed by home-manager; configures `IdentityAgent` to the 1Password socket

### Vault & item conventions

All infrastructure secrets live in the **Private** vault:

| Secret | Vault | Item name | Field(s) |
|---|---|---|---|
| AWS IAM access keys | `Private` | `AWS Personal` | `access_key_id`, `secret_access_key` |
| GitHub PAT | `Private` | `GitHub PAT nix-configs` | `token` |
| Nix cache signing key | `github_nix-configs` | `Nix Cache Signing Key` | `private_key`, `public_key` |

Secret reference format: `op://Private/<item name>/<field name>`

### Injecting secrets in scripts

Use `op read` inline at the point of use:

```bash
export AWS_ACCESS_KEY_ID=$(op read "op://Private/AWS Personal/access_key_id")
export AWS_SECRET_ACCESS_KEY=$(op read "op://Private/AWS Personal/secret_access_key")
export GITHUB_TOKEN=$(op read "op://Private/GitHub PAT nix-configs/token")
```

The `.op-env` file at the repo root documents all required secrets as `op://` references.

## AWS Isolation

- AWS credentials are injected at runtime via `op read` — never stored on disk or in env files
- Never relies on default credentials or AWS profiles
- OIDC role for GitHub Actions (`nix-configs-github-actions`) is scoped to this repo only

### IAM Identity Center & multi-account setup (planned)

> Current setup uses IAM access keys (stored in 1Password). This is a stepping stone.

Goal: migrate to **AWS IAM Identity Center (SSO)** for a multi-account-ready credential setup.

- IAM Identity Center provides short-lived credentials via browser-based login — no long-lived keys
- Investigate whether the **1Password SSH agent + CLI** approach extends naturally to SSO credential caching, or whether a dedicated tool is needed
- Candidate tool: **[Granted](https://docs.commonfate.io/granted/introduction)** (by Common Fate) — CLI for assuming IAM Identity Center roles across multiple accounts with a clean `assume` workflow
- Decision to be made: 1Password-native vs Granted, based on multi-account UX and nix integration
- Once decided: update justfile recipes and remove IAM access keys from 1Password

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

> **Planned:** auto-generate changelog via CI on merge to `main`.

- **`CHANGELOG.md`** auto-generated from conventional commit messages using `git-cliff`
- Generated by CI on every merge to `main` — not maintained by hand
- `git-cliff` will be available in the devShell via `just changelog` for local preview

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
4. Open a PR — CI validates (`nix flake check`)
5. Merge via GitHub UI (squash merge) — branch is auto-deleted
6. Deploy: `just deploy <host>`

PRs are squash-merged to keep a clean commit history on `main`. No review required (solo repo). On merge to `main`, CI will auto-update `CHANGELOG.md` via `git-cliff` *(planned — item #5)*.

## Pre-commit Hooks

Installed automatically when entering the devShell (`nix develop`):

- **nixfmt** — formats all staged `.nix` files and re-stages them
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
