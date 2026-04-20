{ pkgs }:
pkgs.mkShell {
  packages = with pkgs; [
    # Infrastructure
    opentofu
    awscli2
    just

    # Nix tools
    nil # nix LSP
    nixfmt-rfc-style # formatter

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
    HOOKEOF
    chmod +x .git/hooks/pre-commit

    # Inject secrets from 1Password (skip in CI where they are provided by the runner)
    if [ -z "''${CI:-}" ] && command -v op &>/dev/null; then
      export GH_TOKEN=$(op read "op://github_nix-configs/GitHub PAT nix-configs/token")
      export AWS_ACCESS_KEY_ID=$(op read "op://Private/AWS Personal/access_key_id")
      export AWS_SECRET_ACCESS_KEY=$(op read "op://Private/AWS Personal/secret_access_key")
    fi

    # Use a project-scoped AWS profile so host profiles don't interfere.
    # This profile only contributes the region; credentials come from the op read above.
    export AWS_CONFIG_FILE="''${PWD}/.aws/config"
    export AWS_PROFILE=nix-configs

    echo "nix-configs devShell loaded"
    echo "Run 'just --list' to see available recipes"
  '';
}
