{ pkgs, lib, ... }:

let
  # $HOME for shell (zsh expands it); ~ for SSH config (ssh_config doesn't expand $HOME)
  onePasswordAgentSockShell = "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
  onePasswordAgentSockSsh = "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
in
{
  imports = [
    ./ghostty.nix
    ./modules/aerospace.nix
  ];

  # Link GUI apps from `home.packages` into ~/Applications/Home Manager Apps/ so Finder
  # and Spotlight can see them. (HM ≥25.11 defaults this off; Nix profile ~/.nix-profile/Applications
  # is often not indexed by Spotlight.)
  targets.darwin.linkApps.enable = true;

  # macOS-specific packages
  home.packages = with pkgs; [
    coreutils # GNU coreutils on macOS
    gnused
    gnugrep
    _1password-cli
    awscli2
  ];

  # Point SSH_AUTH_SOCK at the 1Password agent so git SSH signing works.
  # Prune broken Homebrew completion dirs from fpath *before* home-manager runs compinit
  # (~570): stale `_brew` (symlink target missing) causes `compinit:527: no such file or directory`.
  programs.zsh.initContent = lib.mkMerge [
    (lib.mkOrder 550 ''
      for _brew_site in /opt/homebrew/share/zsh/site-functions /usr/local/share/zsh/site-functions; do
        if [[ -d "$_brew_site" ]] && [[ ! -r "$_brew_site"/_brew ]]; then
          _new_fpath=()
          for _p in $fpath; do
            if [[ "$_p" != "$_brew_site" ]]; then
              _new_fpath+=("$_p")
            fi
          done
          fpath=($_new_fpath)
          unset _new_fpath _p
        fi
      done
      unset _brew_site
    '')
    ''
      export SSH_AUTH_SOCK="${onePasswordAgentSockShell}"
      source ${
        pkgs.runCommand "op-completions" { HOME = "/tmp"; } ''
          ${pkgs._1password-cli}/bin/op completion zsh > $out
        ''
      }
    ''
  ];

  # 1Password SSH agent key selection is host-specific — see each host's home.nix
  # for the agent.toml that controls which keys are exposed on that machine.

  # SSH config — use 1Password SSH agent for all connections
  # OrbStack's include must come first (before any Host blocks)
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [ "~/.orbstack/ssh/config" ];
    # Path contains a space ("Group Containers") — wrap in literal quotes so ssh_config parses it correctly
    matchBlocks."*".identityAgent = ''"${onePasswordAgentSockSsh}"'';
  };
}
