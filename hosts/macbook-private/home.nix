{ pkgs, ... }:

{
  imports = [
    ../../home/common.nix
    ../../home/darwin.nix
  ];

  # Private macbook specific config
  home.username = "julius";
  home.homeDirectory = "/Users/julius";

  # Add personal-only tools here
  home.packages = with pkgs; [
    # personal tools
  ];
}
