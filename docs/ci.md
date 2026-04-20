# CI job graph

```mermaid
flowchart TD
    PR([Pull request / push])

    subgraph "Always skipped on chore/release-* branches"
        changes["changes\n(ubuntu)\ndetect file groups"]
    end

    subgraph "Skipped when no nix files changed"
        check-flake["check-flake\n(macos-14)\nnix flake check\n+ build serenity"]
    end

    subgraph "Only on chore/release-* branches"
        validate-release["validate-release\n(ubuntu)\ncheck tag + changelog"]
    end

    ci-passed["ci-passed\n(ubuntu)\nfan-in aggregator\n★ required status check"]

    subgraph "Push to main only"
        push-cache["push-cache\n(macos-14)\nsign + push closure\nto S3 cache"]
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
