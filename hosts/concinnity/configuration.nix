{
  pkgs,
  inputs,
  self,
  ...
}:

let
  aikidoNixCa = "/Library/Application Support/AikidoSecurity/EndpointProtection/run/endpoint-protection-nix-combined-ca.pem";
in
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Aikido endpoint protection intercepts TLS. Its Nix bundle has the system
  # roots plus the Aikido CA. ssl-cert-file is for the daemon's own downloads
  # (Aikido writes the same line into the nix.conf store file, but a deploy
  # that changes nix.conf drops it). NIX_SSL_CERT_FILE is for shells, Nix
  # programs (for example Python in a devshell) and, through nix-darwin, the
  # daemon and its fetchers (in `environment` below). If Aikido goes away,
  # remove both.
  nix.settings.ssl-cert-file = aikidoNixCa;

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
    ];
  };

  users.users."julius.blank" = {
    name = "julius.blank";
    home = "/Users/julius.blank";
  };

  # home-manager owns compinit (with -C caching) and starship replaces the prompt.
  # Disabling these avoids a redundant ~700ms compinit + ~16ms promptinit in /etc/zshrc.
  programs.zsh = {
    enable = true;
    enableGlobalCompInit = false;
    promptInit = "";
  };

  environment = {
    # The Aikido CA bundle (see nix.settings.ssl-cert-file above)
    variables.NIX_SSL_CERT_FILE = aikidoNixCa;

    # Ensure Homebrew paths are available in the shell
    systemPath = [
      "/opt/homebrew/bin"
      "/opt/homebrew/sbin"
    ];

    # System-level packages — keep minimal; most GUI apps are managed by IRU.
    # NB: the Claude *desktop app* (Claude.app chat client) is provided by IRU;
    # `claude-code` here is the CLI dev tool, a separate product not shipped by IRU.
    systemPackages = with pkgs; [
      vim
      claude-code
    ];
  };

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
