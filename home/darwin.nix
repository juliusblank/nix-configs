{ pkgs, ... }:

{
  # macOS-specific packages
  home.packages = with pkgs; [
    coreutils # GNU coreutils on macOS
    gnused
    gnugrep
  ];

  # SSH config — use 1Password SSH agent for all connections
  programs.ssh = {
    enable = true;
    extraConfig = ''
      Host *
        IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    '';
  };
}
