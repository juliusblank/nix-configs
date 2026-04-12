# nix-configs

Multi-system nix configuration for macOS and NixOS hosts.

## Hosts

| Host            | OS    | Purpose        |
|-----------------|-------|----------------|
| serenity        | macOS | Personal dev   |
| macbook-work    | macOS | Work dev       |
| pi-moodpi       | NixOS | Moodpi service |

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

3. **AWS CLI configured** with a `personal` profile:
   ```bash
   aws configure --profile personal
   ```

4. **GitHub PAT** — create at https://github.com/settings/tokens
   Scopes: `repo`, `admin:org`, `delete_repo` (optional)

## Getting Started

```bash
# Clone the repo
git clone git@github.com:juliusblank/nix-configs.git ~/personal/nix-configs
cd ~/personal/nix-configs

# Enter the dev shell (provides tofu, awscli, age, etc.)
nix develop

# Step 0a: Create S3 bucket + DynamoDB table for OpenTofu state
just setup-terraform-backend

# Step 0b: Provision GitHub repo config + AWS OIDC + cache bucket
export GITHUB_TOKEN=ghp_your_token_here
just setup-github

# Step 0c: Generate nix cache signing keys (once per machine)
just setup-nix-cache-keys

# Step 1: Deploy to current host
just deploy serenity
```

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
│   ├── macbook-work/      # nix-darwin + home-manager
│   └── pi-moodpi/         # NixOS + home-manager
├── modules/               # reusable nix modules
├── overlays/              # custom packages / overrides
├── secrets/               # agenix-encrypted secrets
├── terraform/             # GitHub + AWS infrastructure
├── .github/workflows/     # CI
└── docs/
    └── SPEC.md            # living specification
```

## AWS Isolation

All AWS operations explicitly use `AWS_PROFILE=personal`. The dev shell
sets this automatically. Never relies on default credentials — safe to
use on work machines.

## Git Identity Isolation

- Default identity: `Julius Blank <dev@juliusblank.de>` (from `home/common.nix`)
- Work machine: repos under `~/work/` automatically use work email via `includeIf`
- This repo lives under `~/personal/` → always uses personal identity

## Secrets

Uses [agenix](https://github.com/ryantm/agenix). Secrets are encrypted
at rest using age keys derived from SSH host keys. See `secrets/` directory.

## Workflow

1. Update `docs/SPEC.md` with desired changes
2. Use Claude (or Claude Code) with spec as context to generate nix config
3. Test locally: `just check` / `just build <host>`
4. Commit and push — CI validates
5. Deploy: `just deploy <host>`
