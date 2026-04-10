{
  description = "juliusblank's multi-system nix configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # macOS system management
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # User-level config (cross-platform)
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, agenix, ... }:
    let
      # Helper to reduce boilerplate
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-darwin" # Apple Silicon Macs
        "x86_64-linux"   # Standard Linux
        "aarch64-linux"  # Raspberry Pi
      ];
    in
    {
      # --- Dev Shell (used by `nix develop`) ---
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              # Infrastructure
              terraform
              awscli2
              just

              # Secrets
              age
              agenix.packages.${system}.default

              # Nix tools
              nil         # nix LSP
              nixfmt-rfc-style  # formatter

              # General
              git
              jq
            ];

            shellHook = ''
              echo "nix-configs devShell loaded"
              echo "Run 'just --list' to see available recipes"
              export AWS_PROFILE=personal
            '';
          };
        }
      );

      # --- macOS (nix-darwin) hosts ---
      darwinConfigurations = {
        macbook-private = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            ./hosts/macbook-private/configuration.nix
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.julius = import ./hosts/macbook-private/home.nix;
            }
            agenix.darwinModules.default
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
            agenix.darwinModules.default
          ];
        };
      };

      # --- NixOS hosts ---
      nixosConfigurations = {
        pi-moodpi = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            ./hosts/pi-moodpi/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.julius = import ./hosts/pi-moodpi/home.nix;
            }
            agenix.nixosModules.default
          ];
        };
      };
    };
}
