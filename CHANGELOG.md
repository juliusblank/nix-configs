# Changelog

Generated from conventional commit messages via [git-cliff](https://github.com/orhun/git-cliff).
## v2026.10.13 — 2026-10-26

### Bug Fixes
- **home:** move Zellij sockets to ~/.cache/zj for longer session names (#136)
- **home:** zse drops Claude Code session markers before starting Zellij (#139)
- **home:** match home-manager Firefox bundle ID in AeroSpace (#141)
- **ci:** upstream watch falls back to date check on API errors (#151)
- **darwin:** work around lost LaunchServices pid for wrapped Firefox (#142)

### Chores
- **changelog:** update CHANGELOG.md for v2026.10.12 (#132)
- **deps:** upgrade to nixpkgs, nix-darwin and home-manager 26.05 (#134)

### Documentation
- **spec:** roadmap #33 — fix git push, gh and prek in the Claude Code sandbox (#135)

### Features
- **concinnity:** declare jbl-personal marketplace and plugins in Nix (#133)
- **home:** Explorations — /explore skill, docs/explorations and zse explore use case (#137)
- **home:** add zse stop --all; mark nixpkgs 26.05 done in SPEC (#138)
- **concinnity:** enable deploy-on-aws plugin and add uv (#140)
- **home:** float short-lived apps in AeroSpace (#144)
- **ci:** upstream watch with daily reminders (#145)
- **concinnity:** notify when ykman waits for a YubiKey touch (#143)
## v2026.10.12 — 2026-10-17

### Bug Fixes
- **devshell:** install pre-commit hook in linked worktrees (#127)

### CI/CD
- move macOS jobs from the retiring macos-14 image to macos-15 (#128)
- build each host once, cancel superseded PR runs, add Dependabot (#129)
- bump the github-actions group with 7 updates (#130)
- **labels:** expand PR labels: devshell, type:* by branch, status:* (#131)

### Chores
- **changelog:** update CHANGELOG.md for v2026.10.11 (#122)

### Features
- **home:** zse project layout shows agent status; agents tab scoped to repo (#123)
- **home:** zse restart stops and restores sessions to pick up a new layout (#125)
## v2026.10.11 — 2026-10-16

### Bug Fixes
- **home:** zse keeps session names in devshell repos; panes load their devshell via zse-env (#121)

### Chores
- **changelog:** update CHANGELOG.md for v2026.10.10 (#120)
## v2026.10.10 — 2026-10-16

### Features
- **home:** CI pane for review, worktree-aware git pane, tig refresh (#118)
- **home:** zse session registry and zse <verb> CLI; no Zellij resurrection (#119)
## v2026.10.9 — 2026-10-16

### Bug Fixes
- **home:** zsek deletes the session by default; zsek -k keeps it (#116)
## v2026.10.8 — 2026-10-15

### Chores
- **changelog:** update CHANGELOG.md for v2026.10.7 (#113)

### Features
- **home:** show tabs in zse layouts via zellij compact-bar (#114)
## v2026.10.7 — 2026-10-14

### Bug Fixes
- **home:** give each zse session its own Claude conversation (#112)

### Chores
- **changelog:** update CHANGELOG.md for v2026.10.6 (#111)
## v2026.10.6 — 2026-10-14

### Chores
- **changelog:** update CHANGELOG.md for v2026.10.5 (#108)

### Documentation
- sync spec and docs with code (#109)

### Features
- **home:** export ZSE_USE_CASE in every zse claude pane (#110)
- **home:** zsh completion for `just deploy` hosts and refs (#107)
## v2026.10.5 — 2026-10-14

### Chores
- **changelog:** update CHANGELOG.md for v2026.10.4 (#105)

### Features
- **justfile:** deploy a release or any ref; fold `deployed` into `status` (#106)
## v2026.10.4 — 2026-10-14

### Bug Fixes
- **home:** review layout — use explicit `/review:review` + doc sweep (#91)
- **concinnity:** sign ~/github/jbl-taktile/ commits with the work key (#94)

### Chores
- **changelog:** update CHANGELOG.md for v2026.10.3 (#90)
- **infra:** watch shell.nix in .envrc so hook body changes land immediately (#92)

### Documentation
- **spec:** add row 28 — Nix-ify jbl-personal marketplace once stable (#95)
- remote SSH auth + signing options; SPEC row 29 TODO (#100)
- **spec:** add TODO to fix the Zellij git pane (#102)

### Features
- **home:** zr -l review accepts a GitHub PR URL (#93)
- **home:** rename `zr`/`zrp`/`zrk` → `zse`/`zsep`/`zsek` (#96)
- **concinnity:** allow `aws` outside the Claude Code sandbox (#97)
- **home:** one-stroke Zellij session switcher — `Ctrl Space` + `zss` (#98)
- **home:** `zse -l ticket` creates worktree on `<USER>/<ticket>` branch (#99)
- **home:** enable Claude Code Remote Control in every zse layout (#101)
- **justfile:** record deploys as GitHub Deployments per host (#104)
- **home:** add `daily` Zellij layout with a task-list pane (#103)
## v2026.10.3 — 2026-10-13

### Bug Fixes
- **home:** zr/zrp — attach to exited sessions to trigger resurrection (#84)
- **home:** zrk — rename `status` local to avoid zsh read-only collision (#89)

### Chores
- **changelog:** update CHANGELOG.md for v2026.10.2 (#82)

### Features
- **home:** add use-case Zellij layouts (code, project, ticket, review) (#85)
- **home:** zr/zrp/zrk CLI with use-case + AWS binding (#86)
- **home:** one-time welcome banner in ticket/project/review shell panes (#87)
- **concinnity:** allow `gh` outside the Claude Code sandbox (#88)

### Refactoring
- **home:** extract Zellij config into its own module; swap pane to tig (#83)
## v2026.10.2 — 2026-10-12

### Bug Fixes
- **home:** zr — use `-n` to create a Zellij session with a layout (#79)
- **home:** add status bar back to Zellij `repo` layout (#80)

### Chores
- **changelog:** update CHANGELOG.md for v2026.10.1 (#77)

### Features
- **home:** add Zellij with per-repo layout (#78)
- **home:** add `zrp` for Zellij sessions with Claude's resume picker (#81)
## v2026.10.1 — 2026-10-12

### Bug Fixes
- **flake:** pin homebrew-cask and homebrew-aerospace to pre-postflight_steps commits (#62)
- **home:** remove stray ~/.gitconfig shadow, port needed settings to nix (#58)
- **concinnity:** use exact Firefox bundle path in `login` helper (#56)
- **home:** split git signing key per host (#72)
- **concinnity:** sign personal commits with a dedicated signing key (#74)

### Chores
- **changelog:** update CHANGELOG.md for v2026.09.2 (#60)
- **devshell:** drop per-commit CHANGELOG regeneration (#76)

### Documentation
- add roadmap items #23-24 and sync quick-reference commands (#61)
- reflect per-host signing key split (#73)
- **spec:** add roadmap row #26 — Claude Code session terminal management (#75)
- **spec:** document S3 cache retention / lifecycle policy (#70)

### Features
- **concinnity:** manage claude-code CLI via nix (#64)
- **ci:** auto-label PRs by scope via actions/labeler (#71)
- **aerospace:** include DELL P2419HC as primary external monitor (#67)
- **concinnity:** declare taktile-skills marketplace and plugins for claude-code (#66)
- **home:** add `todo` shell helper for daily-tasks capture (#59)

### Performance
- **ci:** parallelize host builds and cache concinnity closure (#65)
- **serenity:** move telegram from nix to homebrew cask (#68)
- **ci:** run push-cache on same-repo PRs too (#69)
## v2026.09.2 — 2026-09-29

### Bug Fixes
- **flake:** pin homebrew-cask to pre-depends_on-regression commit (#49)
- **lint:** consolidate repeated attribute keys to resolve statix W20 warnings (#52)
- **flake:** unpin nix-homebrew and homebrew-cask (#53)

### Chores
- **changelog:** update CHANGELOG.md for v2026.05.1 (#46)
- **deps:** update flake inputs (#50)

### Features
- **home:** add statix Nix linter to devShell and pre-commit hook (#51)
- **home:** set neovim as default editor and add ... alias (#47)
- **serenity:** add 1Password Firefox extension (#54)
- **home:** install github/gh-stack CLI extension for stacked PRs (#55)
- **justfile:** add deploy status tracking and just status recipe (#57)
- **darwin:** add AeroSpace tiling WM with 6-workspace layout (#48)
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

