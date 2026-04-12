{ pkgs, ... }:

{
  # macOS-specific packages
  home.packages = with pkgs; [
    coreutils # GNU coreutils on macOS
    gnused
    gnugrep
  ];
}
