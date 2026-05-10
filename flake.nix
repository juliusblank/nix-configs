{
  description = "juliusblank's multi-system nix configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code.url = "github:sadjow/claude-code-nix";

    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pinned to brew 5.0.12 for ruby_3_4 compat; upgrade together with nixpkgs when moving to 26.05
    nix-homebrew.url = "github:zhaofengli/nix-homebrew/a5409abd0d5013d79775d3419bcac10eacb9d8c5";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      # Pinned to last commit before `depends_on :macos` (positional symbol) was introduced
      # in rekordbox, audacity, vial, gimp, vlc. brew-5.0.12-patched uses `def depends_on(**kwargs)`
      # which only accepts keyword args; the bare symbol form causes a Ruby ArgumentError.
      # Unpin when homebrew-cask fixes those casks or nix-homebrew is upgraded past 5.0.12.
      url = "github:homebrew/homebrew-cask/4cc961811d146d948050c2565bf8bf772b45d9f7";
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
          default = import ./shell.nix { inherit pkgs; };
        }
      );

      # --- macOS (nix-darwin) hosts ---
      darwinConfigurations = {
        serenity = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = { inherit inputs self; };
          modules = [
            {
              # direnv 2.37.x fish-test is SIGKILL'd in the macOS sandbox; skip checks
              nixpkgs.overlays = [
                (final: prev: {
                  direnv = prev.direnv.overrideAttrs (_: {
                    doCheck = false;
                  });
                })
              ];
            }
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

        concinnity = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = { inherit inputs self; };
          modules = [
            {
              # direnv 2.37.x fish-test is SIGKILL'd in the macOS sandbox; skip checks
              nixpkgs.overlays = [
                (final: prev: {
                  direnv = prev.direnv.overrideAttrs (_: {
                    doCheck = false;
                  });
                })
              ];
            }
            ./hosts/concinnity/configuration.nix
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users."julius.blank" = import ./hosts/concinnity/home.nix;
            }
            nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                enable = true;
                enableRosetta = true;
                user = "julius.blank";
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
