# CI job graph

```mermaid
flowchart TD
    PR([Pull request / push])

    subgraph "Always skipped on chore/release-* branches"
        changes["changes\n(ubuntu)\ndetect file groups"]
    end

    subgraph "Skipped when no nix files changed"
        check-flake["check-flake matrix\n(macos-15 × 2)\nbuild serenity | build concinnity\n(flake check on serenity leg)\nsame-repo PR or push to main:\nsign + push closure to S3 cache"]
    end

    subgraph "Only on chore/release-* branches"
        validate-release["validate-release\n(ubuntu)\ncheck tag + changelog"]
    end

    ci-passed["ci-passed\n(ubuntu)\nfan-in aggregator\n★ required status check"]

    PR --> changes
    PR --> validate-release
    changes -->|nix == true| check-flake
    changes -->|nix == false| ci-passed
    check-flake --> ci-passed
    validate-release --> ci-passed
```

`ci-passed` is the single required branch-protection status check. Skipped jobs count as passing, so a docs-only PR is never blocked waiting for `check-flake` to run.

The cache push runs in the same `check-flake` leg as the build, so each closure is built once. A failed cache step does not fail the leg (`continue-on-error`). Dependabot PRs get no repository secrets or OIDC role, so they only build and never push. A new push to a PR cancels the PR's running CI (`concurrency`); runs on `main` are not cancelled. Dependabot (`.github/dependabot.yml`) opens one grouped PR per week for action updates.

See [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) for the full workflow definition.
