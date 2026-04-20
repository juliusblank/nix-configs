{ pkgs, ... }:

let
  onePasswordAgentSock = "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
in
{
  # macOS-specific packages
  home.packages = with pkgs; [
    coreutils # GNU coreutils on macOS
    gnused
    gnugrep
    _1password-cli
  ];

  # Point SSH_AUTH_SOCK at the 1Password agent so git SSH signing works
  programs.zsh.initExtra = ''
    export SSH_AUTH_SOCK="${onePasswordAgentSock}"
    eval "$(op completion zsh)"
  '';

  # 1Password SSH agent — which keys to expose
  home.file.".config/1password/ssh/agent.toml".text = ''
    # All SSH keys from the Private vault (includes the personal "serenity" key)
    [[ssh-keys]]
    vault = "Private"

    # Claude Code signing key
    [[ssh-keys]]
    item = "Claude github SSH key"
    vault = "github_nix-configs"
  '';

  # SSH config — use 1Password SSH agent for all connections
  # OrbStack's include must come first (before any Host blocks)
  programs.ssh = {
    enable = true;
    includes = [ "~/.orbstack/ssh/config" ];
    extraConfig = ''
      Host *
        IdentityAgent "${onePasswordAgentSock}"
    '';
  };
}
