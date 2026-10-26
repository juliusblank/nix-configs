# Upstream watch

Reminders for upstream issues and PRs that this repo waits on — for example the end of a
workaround (roadmap #35: the Firefox LaunchServices workaround waits on NixOS/nixpkgs#571894
and nikitabobko/AeroSpace#2316).

## How it works

- **One open issue per watched item**, with the label **`upstream-watch`**. The issue body
  holds one fenced `yaml` block with the data; text outside the block is free:

  ````markdown
  Remove the Firefox LaunchServices workaround (roadmap #35) when this is fixed.

  ```yaml
  url: https://github.com/NixOS/nixpkgs/issues/571894
  interval_days: 30
  last_checked: 2026-10-26
  next_check: 2026-11-25
  ```
  ````

- **`.github/workflows/upstream-watch.yml`** runs daily at 06:00 UTC (and on demand via
  *Run workflow*). For each open watch issue, `scripts/upstream-watch.sh check`:
  - comments when the upstream issue / PR (GitHub URLs only) changes state — `open`,
    `closed` or `merged` — and records it as `upstream_state`;
    the workflow token can read only public repos, so items in private repos (for example
    taktile-org) get the date check only;
  - comments once when `next_check` is today or earlier, and records `reminded_on`.
- **After you checked an item**, comment **`/checked`** on the issue (repo owner only). The
  workflow sets `last_checked` to today and `next_check` to today + `interval_days`.
- **Stop watching:** close the issue (for example after you removed the workaround).
- **Current list:** `gh issue list --label upstream-watch` (or the label filter on GitHub).

GitHub notifies you about the comments like about any issue activity.

## Add an item

```bash
gh issue create --label upstream-watch --title "Watch: <short name>" --body-file - <<'MD'
<why we wait, what to do when it is fixed>

```yaml
url: <upstream issue or PR URL>
interval_days: 30
last_checked: <today>
next_check: <today + 30 days>
```
MD
```

## Test locally

```bash
DRY_RUN=1 GH_REPO=juliusblank/nix-configs \
  nix shell nixpkgs#yq-go nixpkgs#coreutils -c scripts/upstream-watch.sh check
```

`DRY_RUN=1` prints the comments and data changes instead of writing them.
