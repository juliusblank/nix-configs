# Changelog

Generated from conventional commit messages via [git-cliff](https://github.com/orhun/git-cliff).
## Unreleased — 2026-05-10

### Bug Fixes
- **flake:** pin homebrew-cask to pre-depends_on-regression commit (#49)
- **lint:** consolidate repeated attribute keys to resolve statix W20 warnings (#52)
- **flake:** unpin nix-homebrew and homebrew-cask

### Chores
- **changelog:** update CHANGELOG.md for v2026.05.1 (#46)
- **deps:** update flake inputs (#50)

### Features
- **home:** add statix Nix linter to devShell and pre-commit hook (#51)
- **home:** set neovim as default editor and add ... alias (#47)
## v2026.05.1 — 2026-05-04

### Bug Fixes
- **home:** kill gpg-agent before GitHub key import to release keyboxd lock (#42)

### Chores
- **changelog:** update CHANGELOG.md for v2026.04.8 (#35)
- **deps:** update flake inputs (#45)

### Features
- concinnity host, GitHub layout, and work/personal isolation (#36)
- **darwin:** declare hostnames via networking.hostName (#39)
- **concinnity:** AWS auth overhaul — aws-vault, granted, Firefox containers, zsh perf (#41)
- **home:** add treesitter and vim aliases to neovim (#43)
- **home:** shell aliases, git aliases, and zsh tweaks from digga (#44)
## v2026.04.8 — 2026-04-24

### Bug Fixes
- **home:** quote IdentityAgent path to handle space in "Group Containers" (#32)

### Chores
- **changelog:** update CHANGELOG.md for v2026.04.7 (#30)
- **deps:** upgrade nixpkgs, nix-darwin, home-manager to 25.11 (#31)

### Features
- **home:** declarative AWS CLI config via home/modules/aws.nix (#33)
## v2026.04.7 — 2026-04-20

### Bug Fixes
- **darwin:** use ~ instead of $HOME in SSH IdentityAgent path (#28)
- **home:** add gnupg to verify GitHub GPG-signed commits (#29)

### Chores
- **changelog:** update CHANGELOG.md for v2026.04.6 (#26)

### Features
- **home:** configure SSH commit signing via 1Password (#27)
## v2026.04.6 — 2026-04-20

### Bug Fixes
- **changelog:** keep v-prefix in section headers to match tag names (#25)
## v2026.04.5 — 2026-04-20

### Bug Fixes
- **release:** use GitHub PAT to open release PR so CI triggers (#23)
## v2026.04.4 — 2026-04-20

### Refactoring
- **ci:** path-aware jobs with fan-in aggregator (#21)
## v2026.04.3 — 2026-04-20

### Bug Fixes
- **release:** hoist GH_TOKEN to job level so gh cli can open PR (#18)
## v2026.04.1 — 2026-04-20

### Bug Fixes
- **serenity:** move 1password-cli from brews to casks
- **infra:** correct IAM role name to nix-configs-github-actions
- **infra:** add empty filter to lifecycle rule to satisfy provider requirement
- **infra:** update CI build step from macbook-private to serenity (#1)
- **infra:** harden CI workflow — real darwin build on every PR (#12)
- **changelog:** pre-commit hook + release PR instead of direct push (#17)

### Documentation
- add CLAUDE.md and update spec with planned changes
- **spec:** fix stale AWS isolation section and mark cache/CI as planned
- **spec:** add planned AWS IAM Identity Center migration
- **spec:** note CI workflow exists, update item 3 notes
- **spec:** expand CI item notes, add nixpkgs 26.05 upgrade task
- **spec:** add tf-apply guardrails and plan-to-file workflow items (#4)
- **spec:** add Code Conventions section and scoped CLAUDE.md files (#5)
- **spec:** audit roadmap status and prep nixpkgs 26.05 notes (#11)

### Features
- replace agenix with 1Password for secrets and SSH management
- **home:** manage ~/.ssh/config via home-manager
- **infra:** add tf-import recipe to justfile
- **flake:** add nixfmt-rfc-style pre-commit hook via devShell
- **infra:** enforce branch+PR workflow, squash-only merges (#2)
- **flake:** add tofu fmt and flake.lock pre-commit hooks (#3)
- **infra:** add tf-apply guardrails (#7)
- **infra:** tf-apply guardrails and plan-to-file workflow (#8)
- **infra:** wire up nix binary cache (#10)
- **infra:** bring state backend under tofu management (#13)
- **changelog:** add git-cliff changelog generation (#15)

### Refactoring
- **infra:** rename github_repository resource to nix_configs
- **devshell:** inject AWS credentials once in shellHook (#14)

