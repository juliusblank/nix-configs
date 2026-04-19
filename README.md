# nix-configs

Multi-system nix configuration for macOS and NixOS hosts.

## Hosts

| Host            | OS    | Purpose        | Status                   |
|-----------------|-------|----------------|--------------------------|
| serenity        | macOS | Personal dev   | active                   |
| macbook-work    | macOS | Work dev       | planned (not deployed)   |
| pi-moodpi       | NixOS | Moodpi service | planned (config pending) |

## Prerequisites

1. **Nix** — install with flakes enabled:
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh
   ```

2. **just** — install via nix or brew:
   ```bash
   nix-env -iA nixpkgs.just
   # or: brew install just
   ```

3. **1Password + 1Password CLI** — install the app and CLI, then sign in:
   ```bash
   brew install 1password 1password-cli
   op signin
   ```
   AWS credentials and the 1Password SA token are stored in the **Private** vault.
   The GitHub PAT lives in the **github/nix-configs** vault.
   All secrets are injected at runtime via `op read` — no manual credential export required.

## Getting Started

```bash
# Clone the repo
git clone git@github.com:juliusblank/nix-configs.git ~/personal/nix-configs
cd ~/personal/nix-configs

# Sign in to 1Password CLI (secrets are injected automatically from here)
op signin

# Enter the dev shell (provides tofu, awscli, just, etc.)
nix develop

# Step 0a: Create S3 bucket + DynamoDB table for OpenTofu state
just setup-terraform-backend

# Step 0b: Provision GitHub repo config + AWS OIDC + cache bucket
just setup-github

# Step 0c: Generate nix cache signing keys (once per machine)
just setup-nix-cache-keys

# Step 1: Deploy to current host
just deploy serenity
```

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
│   ├── macbook-work/      # nix-darwin + home-manager (planned)
│   └── pi-moodpi/         # NixOS + home-manager (planned)
├── overlays/              # custom packages / overrides
├── terraform/             # GitHub + AWS infrastructure (OpenTofu)
├── .github/workflows/     # CI
└── docs/
    └── SPEC.md            # living specification
```

## AWS Isolation

AWS credentials are injected at runtime via `op read` from the 1Password **Private** vault.
They are never stored on disk, in env files, or in AWS profiles. Safe to use on any machine.

## Git Identity Isolation

- Default identity: `Julius Blank <dev@juliusblank.de>` (from `home/common.nix`)
- Work machine: repos under `~/work/` automatically use work email via `includeIf`
- This repo lives under `~/personal/` → always uses personal identity

## Secrets

All secrets live in the **Private** vault in 1Password and are never stored in the repo.
The 1Password SSH agent serves SSH keys to all SSH connections via `IdentityAgent` in
`~/.ssh/config` (managed by home-manager).

| Secret | Vault | 1Password item | Field(s) |
|---|---|---|---|
| AWS IAM access keys | `Private` | `AWS Personal` | `access_key_id`, `secret_access_key` |
| GitHub PAT | `github/nix-configs` | `GitHub PAT nix-configs` | `token` |
| 1Password SA token (CI) | `Private` | `1Password SA github-actions-nix-configs` | `token` |

## Workflow

1. Update `docs/SPEC.md` with desired changes
2. Use Claude (or Claude Code) with spec as context to generate nix config
3. Test locally: `just check` / `just build <host>`
4. Commit and push — CI validates
5. Deploy: `just deploy <host>`
