# Concinnity — after nix-darwin / home-manager is live

Run this checklist once **`just deploy concinnity`** (or `darwin-rebuild switch --flake …#concinnity`) has succeeded and you have opened a **new** terminal.

Canonical repo path: **`~/github/juliusblank/nix-configs`** (see `docs/SPEC.md`).

## 1. Confirm the flake is active

From the repo (with the devShell active — **`direnv allow`** in this repo or
**`nix develop`**):

```bash
just check
just deploy concinnity   # if you only built before
```

Sanity checks:

- `which nvim`, `which gh`, `which starship`, `which lazygit` resolve under the Nix store / home-manager profile.
- Zsh shows Starship; `direnv` loads in cloned repos with `.envrc`.

## 2. Auth and Git signing

1. **1Password** — app unlocked; **`op signin`** if the CLI needs it.
2. **`gh auth login`** — stores credentials outside this repo (Keychain / `gh` state). Home Manager already enables `gh` and the default **git credential helper** for GitHub hosts.
3. **Work commit signing (SSH)** — in **`hosts/concinnity/home.nix`**, complete the TODO: set **`user.signingkey`** in the `workGitIdentity` block using the work key from 1Password (`key::ssh-ed25519 …`).

## 3. Homebrew cleanup

Do this **after** you trust the nix-managed tools on `PATH` (see §1).

### Immediately safe (nix / HM already provide)

Examples (adjust if a formula is not installed):

```bash
brew uninstall awscli direnv tree lazygit starship gh
```

### After work devShell flakes own those workflows

When per-repo shells provide mise / pyenv / pipx / pre-commit / tfenv / mkcert / etc.:

```bash
brew uninstall mise pyenv pipx prek tfenv mkcert lsd neovim
```

Remove Brew **Python@** formulae when nothing on the system needs them.

### Orphans

```bash
brew leaves          # sanity: only what you still want from Homebrew
brew autoremove      # peel transitive formulae (see SPEC — transitive-only policy)
```

Keep **`granted`** and **`aws-vault`** while nix-darwin declares them in **`hosts/concinnity/configuration.nix`**.

## 4. AWS on the work laptop

**`tktliam`** in **`custom.aws`** is still a placeholder until work **`~/.aws.config`** (or Granted SSO) is integrated. Follow your internal process for work AWS access.

## 5. Work dev environments

- Land the **separate work flake** (or shells) and **`.envrc`** / **`use flake …`** under **`~/github/taktile-org/`** repos.
- Then run the **second `brew uninstall` batch** in §3.

## 6. Optional polish

- Set **`programs.neovim.defaultEditor = true`** in **`home/common.nix`** if you want **`EDITOR=nvim`** everywhere.
- Replace the **placeholder** Neovim **`extraLuaConfig`** with a real config when ready.
- **OrbStack:** **`home/darwin.nix`** includes **`~/.orbstack/ssh/config`**. If IRU does not install OrbStack on concinnity, either install it or narrow that include to hosts that have OrbStack.

## 7. Ongoing

- Before pushes: **`just fmt`**, **`just check`**.
- After merging config changes: **`just deploy concinnity`** from the canonical clone path.
