{ pkgs }:
pkgs.mkShell {
  packages = with pkgs; [
    # Infrastructure
    opentofu
    just

    # Nix tools
    nil # nix LSP
    nixfmt-rfc-style # formatter
    statix # linter

    # Changelog
    git-cliff

    # General
    git
    gh
    jq
  ];

  shellHook = ''
    # Install pre-commit hook
    mkdir -p .git/hooks
    cat > .git/hooks/pre-commit << 'HOOKEOF'
    #!/usr/bin/env bash
    set -e

    # Format staged .nix files
    staged_nix=$(git diff --cached --name-only --diff-filter=ACM | grep '\.nix$' || true)
    if [ -n "$staged_nix" ]; then
      echo "==> nixfmt: formatting staged .nix files..."
      echo "$staged_nix" | xargs nixfmt
      echo "$staged_nix" | xargs git add
    fi

    # Lint staged .nix files (runs after nixfmt so it sees formatted code)
    if [ -n "$staged_nix" ] && command -v statix &>/dev/null; then
      echo "==> statix: linting staged .nix files..."
      echo "$staged_nix" | xargs -I{} statix check {}
    fi

    # Format staged .tf files
    staged_tf=$(git diff --cached --name-only --diff-filter=ACM | grep '\.tf$' || true)
    if [ -n "$staged_tf" ]; then
      echo "==> tofu fmt: formatting staged .tf files..."
      echo "$staged_tf" | xargs tofu fmt
      echo "$staged_tf" | xargs git add
    fi

    # Ensure flake.lock is staged when flake.nix changes
    if git diff --cached --name-only | grep -q 'flake\.nix'; then
      if git diff --name-only | grep -q 'flake\.lock'; then
        echo "ERROR: flake.nix is staged but flake.lock has unstaged changes."
        echo "Run: git add flake.lock"
        exit 1
      fi
    fi

    # Regenerate CHANGELOG.md from conventional commits.
    # Only runs inside the devShell where git-cliff is available; silently skipped outside.
    if command -v git-cliff &>/dev/null; then
      git-cliff --output CHANGELOG.md 2>/dev/null
      git add CHANGELOG.md
    fi
    HOOKEOF
    chmod +x .git/hooks/pre-commit

    # Inject secrets from 1Password — only on serenity where the relevant vaults exist.
    # On other machines (concinnity, CI) the secrets are either not needed or provided
    # by the runner environment. This guard prevents op read errors on machines that
    # don't have access to the github_nix-configs or infrastructure vaults.
    if [ -z "''${CI:-}" ] && [ "$(hostname -s)" = "serenity" ] && command -v op &>/dev/null; then
      export GH_TOKEN=$(op read "op://github_nix-configs/GitHub PAT nix-configs/token")
    fi

    # AWS — credentials sourced via credential_process in ~/.aws/config locally;
    # in CI, AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY env vars take precedence over
    # credential_process. AWS_DEFAULT_REGION is a fallback for CI where the config
    # file may not exist. Only set on serenity; concinnity uses its own AWS config.
    if [ -z "''${CI:-}" ] && [ "$(hostname -s)" = "serenity" ]; then
      export AWS_CONFIG_FILE="$HOME/.aws/config"
      export AWS_PROFILE=personal-nix-configs-infra
      export AWS_DEFAULT_REGION=eu-central-1
    fi

    echo "nix-configs devShell loaded"
    echo "Run 'just --list' to see available recipes"
  '';
}
