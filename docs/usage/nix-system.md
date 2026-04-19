# System Configuration Usage

This document covers day-to-day use of the nix-darwin / NixOS system configuration — editing
config, testing changes locally, and deploying to a host.

## How it works

All host configurations are defined in `hosts/<name>/` and composed in `flake.nix`. Shared
user-facing tools and shell setup live in `home/common.nix`; macOS-specific additions go in
`home/darwin.nix`. Changes are always made on a branch, validated locally, then deployed after
merging to `main`.

## Standard workflow

### 1. Create a branch

```bash
git checkout -b feat/serenity-add-starship
```

### 2. Edit configuration

Common files:

| File | What it controls |
|---|---|
| `home/common.nix` | Shell, CLI tools, git identity — applies to every host |
| `home/darwin.nix` | macOS-specific home-manager additions |
| `hosts/serenity/configuration.nix` | System-level config for serenity (nix-darwin) |
| `hosts/serenity/home.nix` | home-manager config specific to serenity |

Example — adding a package to all hosts:

```nix
# home/common.nix
home.packages = with pkgs; [
  ripgrep
  fd
  starship   # <-- add here
];
```

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
```

This produces a `./result` symlink but does not activate anything. Safe to run at any time.

To preview what store paths would change compared to the currently active system:

```bash
just diff serenity
```

### 5. Commit and open a PR

```bash
git add -p
git commit -m "feat(home): add starship to common packages"
git push -u origin feat/serenity-add-starship
gh pr create --fill
```

CI runs `nix flake check` and builds `serenity` on every PR — the build must be green before
merging.

### 6. Deploy after merging

After the PR is squash-merged into `main`:

```bash
git checkout main && git pull
just deploy serenity
```

`just deploy serenity` runs `sudo darwin-rebuild switch --flake .#serenity` and activates the
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
just diff serenity       # show store-path diff vs. active system
just deploy serenity     # build and activate (runs darwin-rebuild switch)
just update              # update flake.lock
```
