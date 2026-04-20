# Changelog

Generated from conventional commit messages via [git-cliff](https://github.com/orhun/git-cliff).
## 2026.04.1 — 2026-04-20

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

