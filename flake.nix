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
              jq
            ];

            shellHook = ''
              # Install nixfmt-rfc-style pre-commit hook
              mkdir -p .git/hooks
              cat > .git/hooks/pre-commit << 'HOOKEOF'
              #!/usr/bin/env bash
              set -e
              staged=$(git diff --cached --name-only --diff-filter=ACM | grep '\.nix$' || true)
              if [ -n "$staged" ]; then
                echo "==> nixfmt-rfc-style: formatting staged .nix files..."
                echo "$staged" | xargs nixfmt
                echo "$staged" | xargs git add
              fi
              HOOKEOF
              chmod +x .git/hooks/pre-commit

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
