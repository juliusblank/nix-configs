{ pkgs, ... }:

{
  imports = [
    ../../home/common.nix
    ../../home/darwin.nix
  ];

  home.username = "julius";
  home.homeDirectory = "/Users/julius";

  # Override git identity for work repos via includeIf
  # Personal identity is the default (from common.nix)
  # Work repos under ~/work/ get the work identity
  programs.git.includes = [
    {
      condition = "gitdir:~/work/";
      contents = {
        user = {
          name = "Julius Blank";       # adjust if work uses different name
          email = "WORK_EMAIL_HERE";   # replace with work email
        };
      };
    }
  ];

  # Convention: this repo lives under ~/personal/
  # so it always uses the personal git identity from common.nix

  home.packages = with pkgs; [
    # work-specific tools
  ];
}
