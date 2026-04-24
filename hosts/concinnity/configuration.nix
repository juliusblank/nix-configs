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

  # No nix binary cache on the work machine — avoid pulling personal store paths
  # onto a work-managed device.

  system.configurationRevision = self.rev or self.dirtyRev or null;

  # Must match the value set when nix-darwin was first installed on this machine
  system.stateVersion = 6;

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    inputs.claude-code.overlays.default
    inputs.nur.overlays.default
  ];

  users.users."julius.blank" = {
    name = "julius.blank";
    home = "/Users/julius.blank";
  };

  system.primaryUser = "julius.blank";

  # Ensure Homebrew paths are available in the shell
  environment.systemPath = [
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
  ];

  programs.zsh.enable = true;

  # System-level packages — keep minimal; most GUI apps are managed by IRU
  environment.systemPackages = with pkgs; [
    vim
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
    loginwindow.LoginwindowText = "concinnity";
    screencapture.location = "~/Pictures/screenshots";
    screensaver.askForPasswordDelay = 10;
  };

  # Additive only (cleanup = "none") — GUI apps are managed by IRU;
  # homebrew is only used for brews that must come from homebrew.
  homebrew = {
    enable = true;
    user = "julius.blank";
    onActivation = {
      autoUpdate = false;
      cleanup = "none";
      upgrade = true;
    };
    taps = [
      "homebrew/core"
    ];
    brews = [
      "granted"
      "aws-vault"
    ];
    # GUI apps are generally managed by IRU (company software distribution);
    # casks here are additive for tools IRU does not provide.
    casks = [ "ghostty" ];
  };
}
