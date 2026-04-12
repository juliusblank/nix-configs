# Nix Config — Specification

> This is a living document. It serves as the single source of truth for what this
> repo manages, and as prompt context for AI-assisted development.

## Goals

- **Consistent tooling** across all personal machines (macOS + Linux)
- **Reproducible** — any machine can be (re)built from this repo
- **Simple** — minimal nix knowledge needed for day-to-day use
- **Secure** — secrets encrypted at rest, no long-lived credentials in CI

## Hosts

| Host              | OS         | Manager             | Purpose           |
|-------------------|------------|----------------------|-------------------|
| serenity          | macOS      | nix-darwin + home-manager | Personal dev     |
| macbook-work      | macOS      | nix-darwin + home-manager | Work dev          |
| pi-moodpi         | NixOS      | NixOS + home-manager      | Moodpi service   |

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

- **OpenTofu** manages: GitHub repo settings, branch protection, OIDC federation, S3 cache bucket (switched from Terraform due to BSL 1.1 license)
- **S3 backend** for OpenTofu state (versioned, locked via DynamoDB)
- **GitHub Actions** for CI: `nix flake check` on push
- **S3 binary cache** for nix store paths (signed, used by all hosts + CI)

## Secrets Management

- **agenix** for nix-level secrets (encrypted with age, keyed to host SSH keys)
- Secrets stored in `secrets/` directory, encrypted at rest
- Each host has its own age key derived from its SSH host key

## AWS Isolation

- All AWS operations use `AWS_PROFILE=personal` explicitly
- Never relies on default credentials
- OIDC role for GitHub Actions is scoped to this repo only

## Git Identity Isolation

- Repo-level `.gitconfig` enforces personal identity
- Work machine uses `includeIf` to switch identity based on repo path (`~/personal/`)

## Development Workflow

1. Update `docs/SPEC.md` with desired changes
2. Use AI assistant (Claude) with spec as context to generate nix config
3. Test locally: `just check` or `just build <host>`
4. Commit and push — CI validates
5. Deploy: `just deploy <host>`
