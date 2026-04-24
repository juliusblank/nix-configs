# Concinnity — after nix-darwin / home-manager is live

Run this checklist once **`just deploy concinnity`** has succeeded and you have opened a **new**
terminal. (A manual **`switch`** must follow current nix-darwin — run **`darwin-rebuild`**
as **root**, e.g. **`sudo "$(nix build --no-link --print-out-paths …#darwin-rebuild)/bin/darwin-rebuild" …`** with the same pin as the **`justfile`**; see *Known issues* in
**`docs/usage/nix-system.md`**.)

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
- **`assume`** / **`login`** prepend the Nix **`yubikey-manager`** bin dir to **`PATH`** before calling **`aws-vault --prompt ykman`**, so Touch / OTP uses the store **`ykman`** even when a Homebrew **`ykman`** exists earlier on the system **`PATH`** (see **`hosts/concinnity/home.nix`**). You can still run **`which ykman`** for curiosity; the functions do not rely on global ordering.
- Zsh shows Starship; `direnv` loads in cloned repos with `.envrc`.

## 2. Auth and Git signing

1. **1Password** — app unlocked; **`op signin`** if the CLI needs it.
2. **`gh auth login`** — stores credentials outside this repo (Keychain / `gh` state). Home Manager already enables `gh` and the default **git credential helper** for GitHub hosts.
3. **Work commit signing (SSH)** — declarative in **`hosts/concinnity/home.nix`** (`workGitIdentity` + **`custom.extraAllowedSigners`** for **`~/.ssh/allowed_signers`**). Work repos under **`~/github/taktile-org/`** and **`~/work/`** use the work key from 1Password (**`github ssh key`**).

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

**`tktliam`** — **`~/.aws/config`** is managed by **`home/modules/aws.nix`** with **`credential_process`** pointing at a nix-wrapped **`granted credential-process --profile tktliam`**. Ensure Granted knows this profile (e.g. **`granted login`** / your org’s Granted onboarding). Then test **`aws --profile tktliam sts get-caller-identity`**. Granted may merge extra SSO blocks into **`~/.aws/config`** at runtime; that is expected.

**Shell (aws-vault):** **`assume`** / **`login`** functions ( **`aws-vault exec` / `login`** with **`ykman`** prompts) and bash-style **`complete`** on profile names live in **`hosts/concinnity/home.nix`** via **`programs.zsh.initContent`** — you do **not** need to paste them into **`~/.zshrc`**.

### `~/.zshrc` (home-manager)

After **`home-manager`** has applied, **`~/.zshrc`** should be the **HM-generated** file (typically a symlink into the generation). Quick checks:

```bash
readlink ~/.zshrc
head -n 5 ~/.zshrc
```

You should see HM’s header (e.g. a “managed by Home Manager” comment). If **`~/.zshrc`** is a plain file you edited by hand, **back it up**, remove it, and run **`home-manager switch`** again so HM can install the symlink. **Remove** duplicate **`assume`** / **`login`** / **`complete`** blocks from any old backup so they are not sourced twice.

**`home/darwin.nix`** prunes a broken Homebrew **`_brew`** completion from **`fpath`** before **`compinit`** (avoids **`compinit:527: … _brew`**); if it still appears, run **`brew update`** / reinstall **`brew`** completions or **`brew completions link`**.

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
