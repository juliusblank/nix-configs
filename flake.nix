{
  description = "juliusblank's multi-system nix configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code.url = "github:sadjow/claude-code-nix";

    # Pinned to last commit using ruby_3_4; upgrade together with nixpkgs when moving to 26.05
    nix-homebrew.url = "github:zhaofengli/nix-homebrew/a5409abd0d5013d79775d3419bcac10eacb9d8c5";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      nix-homebrew,
      ...
    }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-darwin" # Apple Silicon Macs
        "x86_64-linux" # Standard Linux
        "aarch64-linux" # Raspberry Pi
      ];
    in
    {
      # --- Dev Shell (used by `nix develop`) ---
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
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

              # Inject GitHub token for gh CLI (skip in CI where it's provided by the runner)
              if [ -z "''${CI:-}" ] && command -v op &>/dev/null; then
                export GH_TOKEN=$(op read "op://Private/GitHub PAT nix-configs/token")
              fi

              # Use a project-scoped AWS profile so host profiles don't interfere.
              # Credentials are injected at runtime via `op read` in justfile recipes;
              # this profile only contributes the region.
              export AWS_CONFIG_FILE="''${PWD}/.aws/config"
              export AWS_PROFILE=nix-configs

              echo "nix-configs devShell loaded"
              echo "Run 'just --list' to see available recipes"
            '';
          };
        }
      );

      # --- macOS (nix-darwin) hosts ---
      darwinConfigurations = {
        serenity = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = { inherit inputs self; };
          modules = [
            ./hosts/serenity/configuration.nix
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.jbl = import ./hosts/serenity/home.nix;
            }
            nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                enable = true;
                enableRosetta = true;
                user = "jbl";
                autoMigrate = true;
                taps = {
                  "homebrew/homebrew-core" = inputs.homebrew-core;
                  "homebrew/homebrew-cask" = inputs.homebrew-cask;
                };
                mutableTaps = false;
              };
            }
          ];
        };

        macbook-work = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            ./hosts/macbook-work/configuration.nix
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.julius = import ./hosts/macbook-work/home.nix;
            }
          ];
        };
      };

      # --- NixOS hosts ---
      nixosConfigurations = {
        # pi-moodpi = nixpkgs.lib.nixosSystem {
        #   system = "aarch64-linux";
        #   modules = [
        #     ./hosts/pi-moodpi/configuration.nix
        #     home-manager.nixosModules.home-manager
        #     {
        #       home-manager.useGlobalPkgs = true;
        #       home-manager.useUserPackages = true;
        #       home-manager.users.julius = import ./hosts/pi-moodpi/home.nix;
        #     }
        #     agenix.nixosModules.default
        #   ];
        # };
      };
    };
}
