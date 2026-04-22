{ pkgs, ... }:

{
  imports = [
    ../../home/common.nix
    ../../home/darwin.nix
    ../../home/modules/granted.nix
  ];

  home.username = "jbl";
  home.homeDirectory = "/Users/jbl";

  # Firefox with container tabs for multi-account AWS console access
  programs.firefox = {
    enable = true;
    profiles.default = {
      isDefault = true;
      extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
        multi-account-containers
      ];
    };
  };

  # Granted for AWS credential management
  custom.granted.enable = true;
}
