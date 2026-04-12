{ pkgs, ... }:

{
  imports = [
    ../../home/common.nix
    ../../home/darwin.nix
  ];

  home.username = "jbl";
  home.homeDirectory = "/Users/jbl";
}
