{ pkgs, ... }:

{
  imports = [
    ../../home/common.nix
  ];

  home.username = "julius";
  home.homeDirectory = "/home/julius";
}
