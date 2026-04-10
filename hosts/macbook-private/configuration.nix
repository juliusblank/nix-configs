{ pkgs, ... }:

{
  # Nix configuration
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    # S3 binary cache — uncomment after setup-nix-cache
    # substituters = [ "s3://juliusblank-nix-cache?region=eu-central-1" ];
    # trusted-public-keys = [ "juliusblank-nix-cache:REPLACE_WITH_PUBLIC_KEY" ];
  };

  # System-level packages (available to all users)
  environment.systemPackages = with pkgs; [
    vim
  ];

  # Enable Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  # macOS system defaults
  system.defaults = {
    dock.autohide = true;
    finder.AppleShowAllExtensions = true;
    NSGlobalDomain.AppleShowAllExtensions = true;
  };

  # Required for nix-darwin
  system.stateVersion = 6;
  nixpkgs.hostPlatform = "aarch64-darwin";
}
