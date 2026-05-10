{
  pkgs,
  inputs,
  self,
  ...
}:

{
  # Nix binary cache — signing key for `nix copy` / `just push-cache` in 1Password
  # (op://github_nix-configs/Nix Cache Signing Key/private_key).
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    substituters = [ "https://juliusblank-nix-cache.s3.eu-central-1.amazonaws.com" ];
    trusted-public-keys = [
      "juliusblank-nix-cache:4dcYEtIVp1o7kLv6cGGYoMTMhg83XmSjfNA9l+In+SI="
    ];
  };

  system = {
    configurationRevision = self.rev or self.dirtyRev or null;
    # Must match the value set when nix-darwin was first installed on this machine
    stateVersion = 4;
    primaryUser = "jbl";
    defaults = {
      dock.autohide = true;
      dock.mru-spaces = false;
      finder = {
        AppleShowAllExtensions = true;
        FXPreferredViewStyle = "Nlsv";
        NewWindowTarget = "Home";
        AppleShowAllFiles = true;
      };
      loginwindow.LoginwindowText = "serenity, ole";
      screencapture.location = "~/Pictures/screenshots";
      screensaver.askForPasswordDelay = 10;
    };
  };

  # Set the nixbld gid to match the existing installation
  ids.gids.nixbld = 350;

  networking = {
    hostName = "serenity";
    computerName = "serenity";
    localHostName = "serenity";
  };

  nixpkgs = {
    hostPlatform = "aarch64-darwin";
    config.allowUnfree = true;
    overlays = [
      inputs.claude-code.overlays.default
      inputs.nur.overlays.default
    ];
  };

  users.users.jbl = {
    name = "jbl";
    home = "/Users/jbl";
  };

  # Ensure Homebrew paths are available in the shell
  environment.systemPath = [
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
  ];

  programs.zsh = {
    enable = true;
    enableGlobalCompInit = false;
    promptInit = "";
  };

  # System-level packages (available before user login)
  environment.systemPackages = with pkgs; [
    vim
    neofetch
    telegram-desktop
    vscode
    claude-code
  ];

  security.pam.services.sudo_local.touchIdAuth = true;

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
      "nikitabobko/tap"
    ];
    brews = [
      "cowsay"
      "granted"
    ];
    casks = [
      "1password"
      "aerospace"
      "ghostty"
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
