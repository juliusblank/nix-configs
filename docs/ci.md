# CI job graph

```mermaid
flowchart TD
    PR([Pull request / push])

    subgraph "Always skipped on chore/release-* branches"
        changes["changes\n(ubuntu)\ndetect file groups"]
    end

    subgraph "Skipped when no nix files changed"
        check-flake["check-flake matrix\n(macos-14 × 2)\nbuild serenity | build concinnity\n(flake check on serenity leg)"]
    end

    subgraph "Only on chore/release-* branches"
        validate-release["validate-release\n(ubuntu)\ncheck tag + changelog"]
    end

    ci-passed["ci-passed\n(ubuntu)\nfan-in aggregator\n★ required status check"]

    subgraph "Push to main only"
        push-cache["push-cache matrix\n(macos-14 × 2)\nsign + push each host closure\nto S3 cache"]
    end

    PR --> changes
    PR --> validate-release
    changes -->|nix == true| check-flake
    changes -->|nix == false| ci-passed
    check-flake --> ci-passed
    validate-release --> ci-passed
    check-flake -->|merge to main| push-cache
```

`ci-passed` is the single required branch-protection status check. Skipped jobs count as passing, so a docs-only PR is never blocked waiting for `check-flake` to run.

See [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) for the full workflow definition.
