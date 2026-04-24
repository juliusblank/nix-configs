{ pkgs, ... }:

let
  # $HOME for shell (zsh expands it); ~ for SSH config (ssh_config doesn't expand $HOME)
  onePasswordAgentSockShell = "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
  onePasswordAgentSockSsh = "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
in
{
  # macOS-specific packages
  home.packages = with pkgs; [
    coreutils # GNU coreutils on macOS
    gnused
    gnugrep
    _1password-cli
    awscli2
  ];

  # Point SSH_AUTH_SOCK at the 1Password agent so git SSH signing works
  programs.zsh.initContent = ''
    export SSH_AUTH_SOCK="${onePasswordAgentSockShell}"
    eval "$(op completion zsh)"
  '';

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
