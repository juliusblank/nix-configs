# Claude Code — Repo conventions

> **REQUIRED: Before doing anything else, read `docs/SPEC.md` in full.
> Do not proceed until you have done so.**

This repo manages nix-darwin and NixOS system configurations for personal machines.

## Repo context

- `hosts/serenity/` — personal MacBook Pro (Apple Silicon, macOS)
- `hosts/concinnity/` — work MacBook (config ready, not yet deployed)
- `hosts/pi-moodpi/` — Raspberry Pi NixOS host (commented out, config pending)
- `home/common.nix` — shared home-manager config for all hosts
- `home/darwin.nix` — macOS-specific home-manager additions
- `flake.nix` — entry point; pinned to `nixpkgs-25.11-darwin` and `nix-darwin-25.11`
- **Clone path (canonical, macOS):** `~/github/juliusblank/nix-configs` on serenity and
  concinnity — outside `~/work/` (see `docs/SPEC.md`)

## Workflow

0. **Read `docs/SPEC.md`** — required at the start of every session before any task
1. For non-trivial changes: update `docs/SPEC.md` first, get approval, then edit config files
2. For small/obvious changes: proceed directly, but mention what was changed and why
3. Always outline the plan before making changes — wait for a go-ahead before editing files
4. After implementing: summarise what changed and suggest next steps
5. **After editing `flake.nix`, `justfile`, or `docs/SPEC.md`**: check `README.md` for
   consistency and update it in the same commit if anything is stale
6. **After a PR is merged that completes a roadmap item, or after a meaningful batch of related
   changes lands on `main`**: remind the user to cut a release via the GitHub Actions
   `release` workflow (`workflow_dispatch` on `.github/workflows/release.yml`). One sentence
   is enough — e.g. _"This would be a good point to cut a release — trigger the release
   workflow in GitHub Actions if you'd like to tag it."_

## Branch & PR Workflow

All changes go through a branch + PR — **never commit directly to `main`**.

1. Create a branch: `git checkout -b <type>/<short-description>`
   (e.g. `feat/serenity-add-tmux`, `fix/flake-ruby-pin`, `docs/spec-backup`)
2. Make changes, run `just fmt` after any `.nix` edits, run `just check`
3. Commit with a conventional commit message
4. Push and open a PR: `gh pr create --fill`
5. **Do not merge the PR yourself** — leave it for the user to merge via the GitHub UI

## Commit style

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(serenity): add 1password SSH agent config
fix(flake): pin nix-homebrew to ruby_3_4-compatible commit
chore(deps): update flake inputs
docs(spec): mark 1password migration as complete
```

Common scopes: `flake`, `serenity`, `concinnity`, `home`, `darwin`, `infra`, `spec`, `deps`.

## Formatting

- Always run `just fmt` after editing any `.nix` file
- `nixfmt-rfc-style` is the formatter — do not hand-format nix files
- Pre-commit hook in the devShell runs `nixfmt` automatically before every commit

## Safety rules

- **Never run `just deploy`** without explicit instruction from the user
- **Always run `just check` then `just build <host>`** before suggesting a deploy
- **Never edit `flake.lock` manually** — use `nix flake update` or `nix flake lock --update-input <name>`
- **Never change `system.stateVersion` or `home.stateVersion`** — these are set once and must not change
- When in doubt about a destructive or hard-to-reverse change: ask first

## 1Password & secrets

Secrets are never stored in the repo. Sensitive values live across two vaults in 1Password.

| Secret | Vault | Item name | Field(s) |
|---|---|---|---|
| AWS IAM access keys | `infrastructure` | `personal-nix-configs-infra` | `access_key_id`, `secret_access_key` |
| GitHub PAT | `github_nix-configs` | `GitHub PAT nix-configs` | `token` |
| 1Password SA token (CI) | `infrastructure` | `github-actions-nix-configs` | `token` |

Inject secrets at the point of use with `op read`:

```bash
export AWS_ACCESS_KEY_ID=$(op read "op://infrastructure/personal-nix-configs-infra/access_key_id")
export TF_VAR_github_token=$(op read "op://github_nix-configs/GitHub PAT nix-configs/token")
```

The `.op-env` file at the repo root documents all required `op://` references. SSH keys are served
by the 1Password SSH agent — `~/.ssh/config` is managed by home-manager and points `IdentityAgent`
to the 1Password socket.

## Language conventions

Per-language conventions live in scoped `CLAUDE.md` files that are active when working inside
that directory:

- `terraform/CLAUDE.md` — HCL (OpenTofu)
- `.github/CLAUDE.md` — YAML (GitHub Actions)

Nix conventions are below (root `CLAUDE.md` covers the whole repo).

## Nix conventions

- Prefer `with pkgs;` in package lists for readability
- Keep system packages (`environment.systemPackages`) minimal — prefer home-manager for user-facing tools
- Pin unstable or incompatible inputs to specific commits and always add a comment explaining why
- `allowUnfree = true` is set at the system level; no need to set it per-package
- Public functions and attributes must have a `/**` nixdoc block comment:
  ```nix
  /** Builds the unified shell environment for all hosts. */
  mkShell = { ... }: ...;
  ```
