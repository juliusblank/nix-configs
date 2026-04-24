{
  pkgs,
  inputs,
  self,
  ...
}:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Nix binary cache — uncomment after running `just setup-nix-cache-keys` and
  # storing the private key in 1Password (op://github_nix-configs/Nix Cache Signing Key/private_key).
  # Replace the placeholder below with the contents of ~/.config/nix-cache-keys/cache-pub-key.pem.
  nix.settings.substituters = [ "https://juliusblank-nix-cache.s3.eu-central-1.amazonaws.com" ];
  nix.settings.trusted-public-keys = [
    "juliusblank-nix-cache:4dcYEtIVp1o7kLv6cGGYoMTMhg83XmSjfNA9l+In+SI="
  ];

  system.configurationRevision = self.rev or self.dirtyRev or null;

  # Must match the value set when nix-darwin was first installed on this machine
  system.stateVersion = 4;

  # Set the nixbld gid to match the existing installation
  ids.gids.nixbld = 350;

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    inputs.claude-code.overlays.default
    inputs.nur.overlays.default
  ];

  users.users.jbl = {
    name = "jbl";
    home = "/Users/jbl";
  };

  system.primaryUser = "jbl";

  # Ensure Homebrew paths are available in the shell
  environment.systemPath = [
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
  ];

  programs.zsh.enable = true;

  # System-level packages (available before user login)
  environment.systemPackages = with pkgs; [
    vim
    neofetch
    telegram-desktop
    vscode
    lazygit
    claude-code
  ];

  security.pam.services.sudo_local.touchIdAuth = true;

  system.defaults = {
    dock.autohide = true;
    dock.mru-spaces = false;
    finder.AppleShowAllExtensions = true;
    finder.FXPreferredViewStyle = "Nlsv";
    finder.NewWindowTarget = "Home";
    finder.AppleShowAllFiles = true;
    loginwindow.LoginwindowText = "serenity, ole";
    screencapture.location = "~/Pictures/screenshots";
    screensaver.askForPasswordDelay = 10;
  };

  homebrew = {
    enable = true;
    user = "jbl";
    onActivation = {
      autoUpdate = false;
      cleanup = "uninstall";
      upgrade = true;
    };
    taps = [
      "homebrew/core"
      "homebrew/cask"
    ];
    brews = [
      "cowsay"
      "granted"
      "aws-vault"
    ];
    casks = [
      "1password"
      "orbstack"
      "rekordbox"
      "audacity"
      "splice"
      "vial"
      "whatsapp"
      "gimp"
      "vlc"
      "font-bebas-neue"
      "font-rubik-dirt"
      "font-josefin-sans"
      "font-archivo"
      "font-changa-one"
      "font-righteous"
      "font-hammersmith-one"
      "font-special-elite"
      "font-paytone-one"
    ];
  };
}
