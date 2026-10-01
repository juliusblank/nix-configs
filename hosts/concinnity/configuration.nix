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

  system = {
    configurationRevision = self.rev or self.dirtyRev or null;
    # Must match the value set when nix-darwin was first installed on this machine
    stateVersion = 6;
    primaryUser = "julius.blank";
    defaults = {
      dock.autohide = true;
      dock.mru-spaces = false;
      finder = {
        AppleShowAllExtensions = true;
        FXPreferredViewStyle = "Nlsv";
        NewWindowTarget = "Home";
        AppleShowAllFiles = true;
      };
      loginwindow.LoginwindowText = "concinnity";
      screencapture.location = "~/Pictures/screenshots";
      screensaver.askForPasswordDelay = 10;
      # AeroSpace prerequisite — keep one Spaces stack across all displays.
      # Logout required to take effect.
      spaces.spans-displays = true;
      # NOTE: "Reduce motion" (System Settings → Accessibility → Display) is also
      # recommended for AeroSpace, but com.apple.universalaccess is a protected
      # macOS domain that `defaults write` can't touch without Full Disk Access.
      # Toggle it once manually in System Settings.
    };
  };

  networking = {
    hostName = "concinnity";
    computerName = "concinnity";
    localHostName = "concinnity";
  };

  nixpkgs = {
    hostPlatform = "aarch64-darwin";
    config.allowUnfree = true;
    overlays = [
      inputs.claude-code.overlays.default
      inputs.nur.overlays.default
      # Bump aws-vault to v7.10.2 for --backend=op-desktop (1Password Desktop integration).
      # Remove once nixpkgs-25.11-darwin ships ≥ 7.9.3.
      (final: prev: {
        aws-vault = prev.aws-vault.overrideAttrs (old: rec {
          version = "7.10.2";
          src = prev.fetchFromGitHub {
            owner = "ByteNess";
            repo = "aws-vault";
            rev = "v${version}";
            hash = "sha256-d8Rk+Qkfv4fcQYt+U/QF1hF+c03dj2dWHRUtuxIi73U=";
          };
          goModules = old.goModules.overrideAttrs {
            inherit src;
            outputHash = "sha256-dub/57nE3ERKJEsx5bjTWjJBwIeJcmNSYoG/7iZqe+0=";
          };
          ldflags = [
            "-X main.Version=v${version}"
            "-buildid="
          ];
          doInstallCheck = false;
        });
      })
    ];
  };

  users.users."julius.blank" = {
    name = "julius.blank";
    home = "/Users/julius.blank";
  };

  # Ensure Homebrew paths are available in the shell
  environment.systemPath = [
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
  ];

  # home-manager owns compinit (with -C caching) and starship replaces the prompt.
  # Disabling these avoids a redundant ~700ms compinit + ~16ms promptinit in /etc/zshrc.
  programs.zsh = {
    enable = true;
    enableGlobalCompInit = false;
    promptInit = "";
  };

  # System-level packages — keep minimal; most GUI apps are managed by IRU.
  # NB: the Claude *desktop app* (Claude.app chat client) is provided by IRU;
  # `claude-code` here is the CLI dev tool, a separate product not shipped by IRU.
  environment.systemPackages = with pkgs; [
    vim
    claude-code
  ];

  security.pam.services.sudo_local.touchIdAuth = true;

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
      "nikitabobko/tap"
    ];
    brews = [ ];
    # GUI apps are generally managed by IRU (company software distribution);
    # casks here are additive for tools IRU does not provide.
    casks = [
      "aerospace"
      "ghostty"
    ];
  };
}
