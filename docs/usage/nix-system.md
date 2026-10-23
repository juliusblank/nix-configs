# System Configuration Usage

This document covers day-to-day use of the nix-darwin / NixOS system configuration — editing
config, testing changes locally, and deploying to a host.

## How it works

All host configurations are defined in `hosts/<name>/` and composed in `flake.nix`. Shared
user-facing tools and shell setup live in `home/common.nix`; macOS-specific additions go in
`home/darwin.nix`. Changes are always made on a branch, validated locally, then deployed after
merging to `main`.

## Installing Nix (macOS)

Canonical command for this repository:

```bash
curl -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install --enable-flakes
```

This is the [Nix Installer Working Group](https://github.com/NixOS/experimental-nix-installer)
**upstream** installer (served from `artifacts.nixos.org`), with flakes enabled via
**`--enable-flakes`**. It is suitable for hosts where **nix-darwin** will manage Nix
(default **`nix.enable`**).

**Next:** open a **new** terminal, confirm **`nix`** works, then continue with *First-time
nix-darwin* below (clone repo → devShell → **`just build`**, **`just deploy`**).

## First-time nix-darwin (new Mac)

The **`nix-darwin-26.05`** flake has **no** **`darwin-installer`** attribute (upstream
removed it from the flake outputs). Install nix-darwin by running **`darwin-rebuild switch`**
once — [nix-darwin README — Installing nix-darwin](https://github.com/nix-darwin/nix-darwin?tab=readme-ov-file#step-2-installing-nix-darwin).

**From this repo** (same pin as **`flake.nix`** / **`justfile`**): clone to
**`~/github/juliusblank/nix-configs`**, **`cd`** there, enter the devShell (**`nix develop`**
or **`direnv allow`**), then:

```bash
just build <host>    # optional; host = serenity | concinnity
just deploy <host>   # first activation = same recipe as later deploys
```

**Without `just`:**

```bash
cd ~/github/juliusblank/nix-configs
sudo nix run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake ".#<host>"
```

Then open a **new** terminal if needed. See **`README.md`** for serenity vs concinnity paths.

## Standard workflow

### 1. Create a branch

```bash
git checkout -b feat/home-tweak-example
```

### 2. Edit configuration

Common files:

| File | What it controls |
|---|---|
| `home/common.nix` | Shell, Starship, `gh`, CLI tools, git identity — applies to every host |
| `home/darwin.nix` | macOS-specific home-manager additions |
| `hosts/serenity/configuration.nix` | System-level config for serenity (nix-darwin) |
| `hosts/serenity/home.nix` | home-manager config specific to serenity |
| `hosts/concinnity/configuration.nix` | System-level config for concinnity (work Mac) |
| `hosts/concinnity/home.nix` | home-manager config for concinnity (work identity, SSH agent scope) |

Example — adding a package to all hosts:

```nix
# home/common.nix
home.packages = with pkgs; [
  ripgrep
  fd
  hyperfine # <-- example package
];
```

Starship is enabled via `programs.starship` in `home/common.nix` (not `home.packages`).

### 3. Format and validate

Always run the formatter after editing any `.nix` file:

```bash
just fmt
```

Then check the flake evaluates without errors:

```bash
just check
```

### 4. Build without deploying

Build the target host to catch any remaining evaluation errors before activating:

```bash
just build serenity
# or: just build concinnity
```

This produces a `./result` symlink but does not activate anything. Safe to run at any time.

To preview what store paths would change compared to the currently active system:

```bash
just diff serenity
# or: just diff concinnity
```

(`just diff` uses **`nix run …#darwin-rebuild build`** (no root); **`just deploy`** uses a
store-qualified **`darwin-rebuild`** under **`sudo`** for **`switch`** — see *Known issues:
macOS and nix-darwin* below.)

### 5. Commit and open a PR

```bash
git add -p
git commit -m "feat(home): add hyperfine to common packages"
git push -u origin feat/home-tweak-example
gh pr create --fill
```

CI runs `nix flake check --no-build` and builds both `serenity` and `concinnity` (matrix) on
every PR that touches nix files — the build must be green before merging. See `docs/ci.md`.

### 6. Deploy after merging

After the PR is squash-merged into `main`:

```bash
git checkout main && git pull
just deploy serenity
```

`just deploy serenity` runs **`nix build …#darwin-rebuild --print-out-paths`**, then
**`sudo <store>/bin/darwin-rebuild switch --flake .#serenity`** (same nix-darwin pin as
**`flake.nix`** via **`nix_darwin_flake`** in the **`justfile`**; no **`darwin-rebuild`** on
**`PATH`** required) and activates the
new configuration immediately. For NixOS hosts the command prints the remote `nixos-rebuild`
invocation to run instead.

## Updating flake inputs

To pull in the latest packages from the pinned nixpkgs channel:

```bash
just update       # updates all inputs in flake.lock
just check        # verify nothing broke
just build serenity
```

Commit the updated `flake.lock` as a chore:

```bash
git commit flake.lock -m "chore(deps): update flake inputs"
```

## Quick reference

```bash
just fmt                 # format all .nix files
just check               # evaluate and type-check the flake
just build serenity      # build serenity without activating
just build concinnity    # build concinnity without activating
just diff serenity       # show store-path diff vs. active system
just deploy serenity     # build and activate (sudo + store-path darwin-rebuild switch)
just deploy concinnity   # same for concinnity
just deploy concinnity release  # deploy the newest release tag
just status              # active generation, HEAD drift, GitHub deployments per host
just update              # update flake.lock
just gc                  # delete all old generations and collect garbage
```

## Deploying a release or another ref

`just deploy <host>` deploys the current checkout. An optional second
argument deploys a ref instead:

```bash
just deploy concinnity release      # newest v* tag
just deploy concinnity v2026.10.3   # a specific tag (e.g. to roll back)
just deploy concinnity main         # origin/main, freshly fetched
just deploy concinnity feat/x       # origin/feat/x, to test a PR branch
```

With a ref, the recipe fetches, checks the ref out detached, deploys, and
switches back to where you were, also when the deploy fails. It refuses
to start when tracked files have uncommitted changes. It warns when the
deploy is neither `main` nor a release tag.

## Deploy tracking on GitHub

After a successful `darwin-rebuild switch`, `just deploy <host>` records a
[GitHub Deployment](https://docs.github.com/en/rest/deployments) with
environment `<host>` for the deployed commit. The repo sidebar then shows
the commit each host runs ("Deployments", or `/deployments`), and a PR
shows "deployed to `<host>`" when its head commit was deployed. The
description names what was deployed (`release v…`, `branch …` or
`commit …`), the generation, and whether the tree was dirty.

The record is best effort: if the commit is not pushed, or `gh` fails,
`just deploy` prints a warning and the deploy itself still counts. The
ground truth stays on the host: `darwin-version --json` returns
`configurationRevision` (set from `self.rev` / `self.dirtyRev`).
`just status` prints both (the `Revision:` line and the `GitHub
deployments:` section), so you can see drift, for example after a manual
`darwin-rebuild switch` that bypassed the recipe.

## Known issues: macOS and nix-darwin

- **Zellij sessions "stopped" after a deploy** — Zellij keeps its sessions per socket
  dir and protocol version (`~/.cache/zj/contract_version_<n>/` via `ZELLIJ_SOCKET_DIR`;
  0.43 used `$TMPDIR/zellij-<uid>/<version>/`); a new client cannot see servers in another
  dir, so `zse ls` shows them as `stopped` while they still run. **`just deploy`** checks for
  this: when the deploy changes the Zellij version and sessions are running, it asks to stop
  them before the switch and runs `zse restore` after it. Run such deploys **outside Zellij**
  (stopping the session you deploy from would end the deploy). The check compares versions
  only: for other changes (e.g. `ZELLIJ_SOCKET_DIR`), run `zse stop --all` before the deploy
  and `zse restore` in a new terminal after it. If you missed it, stop the old servers with
  the old binary (and the old `ZELLIJ_SOCKET_DIR`, if it changed), then restore:

  ```bash
  old=$(ls -d /nix/store/*-zellij-<old-version>/bin/zellij | head -1)
  "$old" kill-all-sessions --yes
  zse restore
  ```

- **Firefox: "A copy of Firefox is already open" (macOS 27)** — macOS 27 lets only
  Mozilla-signed apps write to **`~/Library/Application Support/Firefox`**. The nixpkgs build
  cannot lock its profile there and shows this dialog without opening a window
  (NixOS/nixpkgs#535123). Since the 26.05 upgrade, **`home/darwin.nix`** sets
  **`programs.firefox.configPath`** to **`Library/Application Support/org.nixos.firefox`**, and
  the wrapper passes it as **`MOZ_APP_DATA`**. After the first deploy with this change, move
  the existing data **once**, with Firefox closed, from a terminal that has **Full Disk Access**
  (System Settings → Privacy & Security), because the old folder is protected:

  ```bash
  old="$HOME/Library/Application Support/Firefox"
  new="$HOME/Library/Application Support/org.nixos.firefox"
  # home-manager already created $new (profiles.ini, managed profile files): copy the
  # user data into it, keep the managed files, drop the stale lock.
  rsync -a --ignore-existing "$old/Profiles/" "$new/Profiles/"
  rm -f "$new/Profiles/"*/.parentlock
  ```

  Then start Firefox and check bookmarks, containers and logins. Keep **`$old`** until you are
  sure, then delete it.

- **Firefox not managed by AeroSpace, missing from Cmd-Tab (macOS 27)** — LaunchServices
  loses the pid (`-1`) of every app whose bundle executable is a shell wrapper that `exec`s
  the real binary (NixOS/nixpkgs#571894, probably an Apple bug). `aerospace list-apps` does
  not show the app, so no `on-window-detected` rule applies. **Workaround** (roadmap #35):
  **`home/darwin.nix`** overrides **`programs.firefox.package`** so that the real binary is the
  bundle executable again; the wrapper's `MOZ_*` variables go into `Info.plist`
  `LSEnvironment`, and the shell wrapper moves to **`bin/firefox`** (used by Granted).
  `LSEnvironment` applies only to Dock / Spotlight / `open` launches. **Check
  NixOS/nixpkgs#571894 about once a month**; when it is fixed, remove the override and the
  `bin/firefox` path in **`home/modules/granted.nix`**. Other wrapped Nix apps (kitty, Emacs)
  have the same problem.

- **`darwin-rebuild: command not found` in `just diff`** — Recipes run under non-interactive
  **`bash`**, so **`PATH`** often omits **`/run/current-system/sw/bin`** and direnv is not
  applied. **`just diff`** uses **`nix run …#darwin-rebuild build`** with the ref in
  **`nix_darwin_flake`** in the **`justfile`**. You only need **`nix`** on **`PATH`**.

- **`just deploy` / root and `sudo`** — Current nix-darwin expects **`darwin-rebuild switch`**
  to run **as root**. **`just deploy`** runs **`nix build …#darwin-rebuild
  --print-out-paths`**, then **`sudo <that-store>/bin/darwin-rebuild switch`**, so **`sudo`**
  never has to resolve the bare name **`darwin-rebuild`** (which fails: macOS **`sudo`**
  **`secure_path`** omits Nix). Keep **`nix_darwin_flake`** in sync with **`inputs.nix-darwin`**
  in **`flake.nix`** when you bump the pin.

- **Manual `darwin-rebuild switch`** — Prefer **`just deploy <host>`**. If you invoke it by
  hand, run **`sudo` with the store path** (e.g. from **`nix build --print-out-paths
  …#darwin-rebuild`**) or ensure an interactive **`PATH`** includes **`darwin-rebuild`**, then
  follow current nix-darwin’s root requirement for **`switch`**.

- **Nix not managed by nix-darwin** — This flake sets **`nix.settings`** on macOS hosts, so
  **nix-darwin must manage Nix** (default **`nix.enable`**, i.e. **`true`**). If another
  installer owns **`nix.conf`** / the daemon and activation refuses to take over, uninstall
  that stack, reinstall with the **artifacts** one-liner in **`README.md`** (*Prerequisites*
  → **Nix (macOS)**), then bootstrap with **`just deploy <host>`** (or **`sudo nix run …#darwin-rebuild
  switch --flake …`**) as in *First-time nix-darwin* above.
