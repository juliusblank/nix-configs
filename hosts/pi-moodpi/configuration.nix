{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix  # generate with nixos-generate-config
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
  };

  # Networking
  networking.hostName = "pi-moodpi";

  # User
  users.users.julius = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here
    ];
  };

  # SSH
  services.openssh.enable = true;

  # TODO: add moodpi service definition

  system.stateVersion = "24.05";
}
