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
      # macOS updates are installed by hand, after a backup and a rekordbox / driver
      # compatibility check. Security responses and system data files
      # (CriticalUpdateInstall, ConfigDataInstall) stay automatic.
      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;
      # AeroSpace prerequisite — keep one Spaces stack across all displays.
      # Logout required to take effect.
      spaces.spans-displays = true;
      # NOTE: "Reduce motion" (System Settings → Accessibility → Display) is also
      # recommended for AeroSpace, but com.apple.universalaccess is a protected
      # macOS domain that `defaults write` can't touch without Full Disk Access.
      # Toggle it once manually in System Settings.
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
      # VS Code 1.144 moved its bundled ripgrep to @vscode/ripgrep-universal; nixpkgs
      # 26.05's generic.nix still patches the old path (NixOS/nixpkgs#584492, fixed on
      # master). Remove once the fix is backported to the 26.05 branch.
      (_final: prev: {
        vscode = prev.vscode.overrideAttrs (old: {
          postPatch =
            builtins.replaceStrings
              [ "Contents/Resources/app/node_modules/@vscode/ripgrep/bin/rg" ]
              [
                "Contents/Resources/app/node_modules.asar.unpacked/@vscode/ripgrep-universal/bin/darwin-arm64/rg"
              ]
              old.postPatch;
        });
      })
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
    fastfetch
    vscode
    claude-code
  ];

  security.pam.services.sudo_local.touchIdAuth = true;

  homebrew = {
    enable = true;
    user = "jbl";
    onActivation = {
      autoUpdate = false;
      # nix-darwin 26.05 maps cleanup = "uninstall" to `--force-cleanup`, which the
      # Homebrew bundled with the pinned nix-homebrew (7d0038b, 5.1.10) rejects.
      # `--cleanup` does the same. Back to cleanup = "uninstall" after the
      # nix-homebrew upgrade.
      cleanup = "none";
      extraFlags = [ "--cleanup" ];
      upgrade = true;
    };
    greedyCasks = true;
    taps = [
      "homebrew/core"
      "homebrew/cask"
      "nikitabobko/tap"
      "juliusblank/local"
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
      "telegram"
      "rekordbox"
      "audacity"
      "splice"
      "vial"
      "whatsapp"
      "gimp"
      "vlc"
      "microsoft-outlook"
      # Harmonic key analysis. Keep "write to tags" off while storage-migration
      # works on the music files: tag writes change the files and their hashes.
      "juliusblank/local/mixed-in-key" # local tap: see homebrew/local-tap
      "microsoft-auto-update"
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
