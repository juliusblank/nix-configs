# Claude Code — Repo conventions

> **REQUIRED: Before doing anything else, read `docs/SPEC.md` in full.
> Do not proceed until you have done so.**

This repo manages nix-darwin and NixOS system configurations for personal machines.

## Repo context

- `hosts/serenity/` — personal MacBook Pro (Apple Silicon, macOS)
- `hosts/macbook-work/` — work MacBook (placeholder, not yet deployed)
- `hosts/pi-moodpi/` — Raspberry Pi NixOS host (commented out, config pending)
- `home/common.nix` — shared home-manager config for all hosts
- `home/darwin.nix` — macOS-specific home-manager additions
- `flake.nix` — entry point; pinned to `nixpkgs-25.05-darwin` and `nix-darwin-25.05`

## Workflow

0. **Read `docs/SPEC.md`** — required at the start of every session before any task
1. For non-trivial changes: update `docs/SPEC.md` first, get approval, then edit config files
2. For small/obvious changes: proceed directly, but mention what was changed and why
3. Always outline the plan before making changes — wait for a go-ahead before editing files
4. After implementing: summarise what changed and suggest next steps

## Commit style

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(serenity): add 1password SSH agent config
fix(flake): pin nix-homebrew to ruby_3_4-compatible commit
chore(deps): update flake inputs
docs(spec): mark 1password migration as complete
```

Common scopes: `flake`, `serenity`, `macbook-work`, `home`, `darwin`, `infra`, `spec`, `deps`.

> **Planned:** move to a branch + PR workflow (no review required). PRs are squash-merged to keep
> a clean history on `main`. CI runs `nix flake check` on PR open/update, and auto-updates
> `CHANGELOG.md` via `git-cliff` on merge to `main`.

## Formatting

- Always run `just fmt` after editing any `.nix` file
- `nixfmt-rfc-style` is the formatter — do not hand-format nix files

> **Planned:** pre-commit hook in the devShell runs `nixfmt-rfc-style` automatically before every commit.

## Safety rules

- **Never run `just deploy`** without explicit instruction from the user
- **Always run `just check` then `just build <host>`** before suggesting a deploy
- **Never edit `flake.lock` manually** — use `nix flake update` or `nix flake lock --update-input <name>`
- **Never change `system.stateVersion` or `home.stateVersion`** — these are set once and must not change
- When in doubt about a destructive or hard-to-reverse change: ask first

## 1Password & secrets

Secrets are never stored in the repo. All sensitive values live in the **Private** vault in 1Password.

| Secret | Item name | Field(s) |
|---|---|---|
| AWS IAM access keys | `AWS Personal` | `access_key_id`, `secret_access_key` |
| GitHub PAT | `GitHub PAT nix-configs` | `token` |

Inject secrets at the point of use with `op read`:

```bash
export AWS_ACCESS_KEY_ID=$(op read "op://Private/AWS Personal/access_key_id")
export GITHUB_TOKEN=$(op read "op://Private/GitHub PAT nix-configs/token")
```

The `.op-env` file at the repo root documents all required `op://` references. SSH keys are served
by the 1Password SSH agent — `~/.ssh/config` is managed by home-manager and points `IdentityAgent`
to the 1Password socket.

## Nix conventions

- Prefer `with pkgs;` in package lists for readability
- Keep system packages (`environment.systemPackages`) minimal — prefer home-manager for user-facing tools
- Pin unstable or incompatible inputs to specific commits and always add a comment explaining why
- `allowUnfree = true` is set at the system level; no need to set it per-package
