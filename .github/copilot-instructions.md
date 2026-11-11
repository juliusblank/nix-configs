# Copilot code review: nix-configs

Personal nix-darwin / home-manager flake (hosts: serenity, concinnity; pi-moodpi is pending). Review for correctness and these conventions; do not restyle working code.

## Layout
- Hosts: `hosts/<host>/` (system config and host-only home config). Shared home-manager: `home/common.nix`; macOS-only: `home/darwin.nix`; feature modules: `home/modules/`.
- OpenTofu in `terraform/` follows `terraform/CLAUDE.md`; GitHub Actions follow `.github/CLAUDE.md`.
- Flakes only: no channels, no `nix-env`, no imperative installs (brew, pip --user, npm -g). New dependencies go through `flake.nix` inputs.

## Must flag (high priority)
- Any change to `system.stateVersion` or `home.stateVersion`.
- Hand edits to `flake.lock` (only `nix flake update` / `nix flake lock --update-input`).
- Secrets, tokens or keys in the repo. Secrets come from 1Password at the point of use (`op read "op://…"`, assigned first, then exported), never committed.
- A pinned input or package override without a comment explaining why.
- Fetches from URLs without a hash, or not through a flake input.
- Absolute paths to the user's home or checkout where a relative path or a home-manager option works.

## Conventions
- Prefer `programs.<name>`/`services.<name>` modules over `home.packages` when a module exists.
- Keep `environment.systemPackages` minimal; user tools belong in home-manager.
- Use `with pkgs;` in package lists.
- Public functions and attributes need a nixdoc `/** … */` comment.
- Formatting is `nixfmt` (RFC style), linting is `statix`. Flag clear deviations; ignore whitespace-only nits.
- Changes to `flake.nix`, `justfile` or `docs/SPEC.md` must keep `README.md` consistent; non-trivial changes update `docs/SPEC.md`.
- Commits and PR titles use Conventional Commits (scopes: flake, serenity, concinnity, home, darwin, infra, spec, deps).

## Review style
- Lead with real defects: broken evaluation, wrong option names, platform mismatches (darwin vs linux), duplicated config across hosts that belongs in `home/common.nix`.
- Give the file and line, the problem, and a concrete fix. Skip praise and summaries.
