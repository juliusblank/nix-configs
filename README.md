# nix-configs

Multi-system nix configuration for macOS and NixOS hosts.

## Hosts

| Host            | OS    | Purpose        | Status                   |
|-----------------|-------|----------------|--------------------------|
| serenity        | macOS | Personal dev   | active                   |
| concinnity      | macOS | Work dev       | planned (not deployed)   |
| pi-moodpi       | NixOS | Moodpi service | planned (config pending) |

## Prerequisites

1. **Nix** — install with flakes enabled:
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   ```

2. **Repo devShell** — this flake’s shell (see `shell.nix`) provides **`just`**, OpenTofu,
   `nixfmt`, `git-cliff`, etc. Enter it in either way:
   - **`nix develop`** — works on any machine with Nix alone.
   - **`direnv allow`** — in this repo, after [direnv](https://direnv.net/docs/installation.html)
     is installed and hooked into your shell (`.envrc` is `use flake`).

   You do **not** need a global `just` from `nix-env` or Homebrew for normal work in
   this repository.

3. **1Password** — install the app and CLI when you will run recipes or devShell hooks
   that call **`op read`** (serenity infra, GitHub token in the devShell on serenity, etc.).
   On **concinnity**, plain **`just check`** / **`just build concinnity`** do not require
   `op`. Sign in with **`op signin`** before serenity-style setup or when something fails
   on missing secrets.

   AWS credentials and the 1Password SA token for personal infra live in documented
   vaults; see `docs/SPEC.md` — *Secrets Management*.

## Getting Started

**Clone path (both macOS hosts):** `~/github/juliusblank/nix-configs` — see
`docs/SPEC.md` (*Canonical clone path for nix-configs*, *GitHub checkout layout*).

**concinnity — work repos:** clone the `taktile` org under `~/github/taktile-org/`
(work git identity). Do not put `nix-configs` there.

**serenity** runs OpenTofu and gets personal-infra secrets in the devShell.
**concinnity** is the work laptop: deploy from this flake, but skip infra bootstrap
unless you intentionally use the same 1Password items from that machine (see
`docs/SPEC.md` — *Serenity and concinnity isolation*).

### First-time nix-darwin on macOS

On a Mac with Nix + flakes that has **never** had nix-darwin, run **once** before the
first **`just deploy <host>`** (matches the `nix-darwin-25.11` pin in `flake.nix`):

```bash
nix run github:nix-darwin/nix-darwin/nix-darwin-25.11#darwin-installer
```

Follow the installer prompts, then open a **new** terminal. You can **`just build`**
before this step; **`just deploy`** needs nix-darwin installed.

### Getting started: serenity (personal)

```bash
git clone git@github.com:juliusblank/nix-configs.git ~/github/juliusblank/nix-configs
cd ~/github/juliusblank/nix-configs

# Sign in to 1Password CLI (secrets are injected automatically from here)
op signin

# Enter the dev shell (provides tofu, just, etc.) — or use direnv allow in this repo
nix develop

# Step 0a: Create S3 bucket + DynamoDB table for OpenTofu state, then bring
# them (and the IAM user) under tofu management
just setup-terraform-backend
just tf-import-backend
just tf-import-user

# Step 0b: Provision GitHub repo config + AWS OIDC + cache bucket
just setup-github

# Step 0c: Create 1Password Service Account for CI and provision OP_SERVICE_ACCOUNT_TOKEN
# (one-time — see docs/usage/infra.md for full instructions)
just tf-plan   # review, then:
just tf-apply

# Step 0d: Generate nix cache signing keys (once per machine)
just setup-nix-cache-keys

# Step 1: Deploy to serenity
just deploy serenity
```

### Getting started: concinnity (work)

Use the **same clone path** as serenity (`~/github/juliusblank/nix-configs`). If the
repo is not cloned yet:

```bash
git clone git@github.com:juliusblank/nix-configs.git ~/github/juliusblank/nix-configs
cd ~/github/juliusblank/nix-configs
```

**Enter the repo devShell** (flake supplies `just`, OpenTofu, formatters, pre-commit):

- **direnv:** with [direnv](https://direnv.net/docs/installation.html) installed and hooked
  into zsh, run **`direnv allow`** once in this directory (`.envrc` is `use flake`).
- **No direnv:** run **`nix develop`**, or from outside the shell e.g.
  **`nix develop -c just build concinnity`**.

Validate and build (no `sudo` yet):

```bash
just check
just build concinnity
```

**First nix-darwin on this Mac:** if `darwin-rebuild` is not available yet, run the
installer under [First-time nix-darwin on macOS](#first-time-nix-darwin-on-macos), then
open a new terminal.

Activate:

```bash
just deploy concinnity
```

Do **not** run the serenity infra steps (0a–0d) on concinnity unless you mean to
manage that infrastructure from the work machine with the same 1Password access as
serenity. The devShell does not export personal `GH_TOKEN` / AWS profile there by
design.

After the first successful deploy, follow **[docs/usage/concinnity-after-deploy.md](docs/usage/concinnity-after-deploy.md)** (auth, brew cleanup, AWS placeholder, devShells).

## Usage

### System configuration

Manage nix-darwin / NixOS host configuration: editing packages, shell setup, and system
settings, then building and deploying to a host.

See [docs/usage/nix-system.md](docs/usage/nix-system.md) for the full workflow and examples.

### Infrastructure

Manage AWS and GitHub resources via OpenTofu: plan changes, review them, and apply — either
from `main` (standard path) or from a branch (for urgent fixes).

See [docs/usage/infra.md](docs/usage/infra.md) for the full workflow and examples.

## Day-to-Day

```bash
just --list              # show all recipes
just check               # validate flake
just build <host>        # build without activating
just deploy <host>       # build and activate
just diff <host>         # show what would change
just push-cache <host>   # push to S3 binary cache
just fmt                 # format nix files
just update              # update flake inputs
just changelog           # regenerate CHANGELOG.md locally
```

## Repo Structure

```
├── flake.nix              # entry point
├── justfile               # all task recipes
├── home/
│   ├── common.nix         # shared tools + shell config (all hosts)
│   └── darwin.nix         # macOS-specific home additions
├── hosts/
│   ├── serenity/          # nix-darwin + home-manager
│   ├── concinnity/        # nix-darwin + home-manager (planned)
│   └── pi-moodpi/         # NixOS + home-manager (planned)
├── overlays/              # custom packages / overrides
├── terraform/             # GitHub + AWS infrastructure (OpenTofu)
├── .github/workflows/     # CI
└── docs/
    ├── SPEC.md            # living specification
    ├── ci.md              # CI job graph
    └── usage/
        ├── nix-system.md
        └── concinnity-after-deploy.md  # post-deploy checklist (work Mac)
```

## AWS Isolation

On **serenity**, AWS keys for personal infra are read at runtime via `op read` (see
`docs/SPEC.md` for vault layout). They are never committed. **concinnity** uses
host-local AWS profiles from home-manager (`custom.aws`) instead of the serenity
devShell defaults. Details: *AWS Isolation* and *Serenity and concinnity isolation* in
`docs/SPEC.md`.

## Git Identity Isolation

- Default identity: `Julius Blank <dev@juliusblank.de>` (from `home/common.nix`)
- **concinnity:** repos under `~/github/taktile-org/` (and legacy `~/work/`) use work
  email and signing via `includeIf` in `hosts/concinnity/home.nix`
- **Both macOS hosts:** `nix-configs` lives at `~/github/juliusblank/nix-configs`
  (personal GitHub layout), **not** under `~/github/taktile-org/`, so this repo always
  uses the **personal** identity (see `docs/SPEC.md`).

## Secrets

Secrets are never stored in the repo. They live across two 1Password vaults (`Private` and `github_nix-configs`) and are injected at runtime via `op read`.
The 1Password SSH agent serves SSH keys to all SSH connections via `IdentityAgent` in
`~/.ssh/config` (managed by home-manager).

| Secret | Vault | 1Password item | Field(s) |
|---|---|---|---|
| AWS IAM access keys | `Private` | `AWS Personal` | `access_key_id`, `secret_access_key` |
| GitHub PAT | `github_nix-configs` | `GitHub PAT nix-configs` | `token` |
| 1Password SA token (CI) | `Private` | `1Password SA github-actions-nix-configs` | `token` |

## Workflow

1. Update `docs/SPEC.md` with desired changes
2. Use Claude (or Claude Code) with spec as context to generate nix config
3. Test locally: `just check` / `just build <host>`
4. Commit and push — CI validates
5. Deploy: `just deploy <host>`
