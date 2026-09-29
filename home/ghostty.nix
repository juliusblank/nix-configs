{ pkgs, ... }:
{
  # Declarative Ghostty config at ~/.config/ghostty/config.
  #
  # nixpkgs `ghostty` is Linux-only — keep `package = null` on macOS and install Ghostty.app
  # separately (nix-homebrew cask on serenity; IRU or official dmg on concinnity).
  #
  # Spotlight (Cmd+Space) indexes /Applications and ~/Applications; it usually does *not*
  # pick up ~/.nix-profile/Applications. Put Ghostty.app in /Applications (Homebrew cask
  # does this) or open it once from Finder and choose Keep in Dock.
  programs.ghostty = {
    enable = true;
    package = null;
    enableZshIntegration = true;
    settings = {
      "font-family" = "FiraCode Nerd Font Mono";
      "font-size" = 14;
      theme = "0x96f";
      "cursor-style" = "block";
      "cursor-style-blink" = true;
      "background-opacity" = 0.9;
      "window-decoration" = true;
      "window-padding-x" = 5;
      "window-padding-y" = 5;
      "window-padding-balance" = true;
      command = "${pkgs.zsh}/bin/zsh";
      "shell-integration" = "zsh";
      "shell-integration-features" = "cursor,sudo,title";
      "scrollback-limit" = 104857600;
      "copy-on-select" = true;
      "mouse-hide-while-typing" = false;
      "clipboard-paste-protection" = true;
      "confirm-close-surface" = true;
      "quit-after-last-window-closed" = true;
      "window-inherit-working-directory" = false;
      "tab-inherit-working-directory" = false;
      "split-inherit-working-directory" = false;
      "quick-terminal-position" = "top";
      "quick-terminal-autohide" = true;
      keybind = [
        "cmd+opt+left=goto_split:left"
        "cmd+opt+right=goto_split:right"
        "cmd+opt+up=goto_split:top"
        "cmd+opt+down=goto_split:bottom"
        "cmd+d=new_split:right"
        "cmd+shift+d=new_split:down"
        "cmd+w=close_surface"
        "cmd+ctrl+left=resize_split:left,10"
        "cmd+ctrl+right=resize_split:right,10"
        "cmd+ctrl+up=resize_split:up,10"
        "cmd+ctrl+down=resize_split:down,10"
        "cmd+v=paste_from_selection"
        "cmd+shift+v=paste_from_clipboard"
      ];
    };
  };

  home.packages = [ pkgs.nerd-fonts.fira-code ];
}
