{ pkgs, ... }:

{
  # macOS-specific packages
  home.packages = with pkgs; [
    coreutils # GNU coreutils on macOS
    gnused
    gnugrep
  ];

  # SSH config — use 1Password SSH agent for all connections
  # OrbStack's include must come first (before any Host blocks)
  programs.ssh = {
    enable = true;
    includes = [ "~/.orbstack/ssh/config" ];
    extraConfig = ''
      Host *
        IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    '';
  };
}
