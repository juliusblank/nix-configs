{ pkgs, ... }:

let
  # Reads static IAM credentials from 1Password and emits the JSON format
  # AWS CLI credential_process expects.
  # TODO: replace with `granted credential-process` once SSO is configured.
  jblRootCredProcess = pkgs.writeShellScript "aws-creds-jbl-root" ''
    exec ${pkgs.jq}/bin/jq -cn \
      --arg id "$(${pkgs._1password-cli}/bin/op read 'op://Private/aws_root/access_key_id')" \
      --arg secret "$(${pkgs._1password-cli}/bin/op read 'op://Private/aws_root/secret_access_key')" \
      '{"Version":1,"AccessKeyId":$id,"SecretAccessKey":$secret}'
  '';
in
{
  imports = [
    ../../home/common.nix
    ../../home/darwin.nix
    ../../home/modules/granted.nix
    ../../home/modules/aws.nix
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

  # AWS CLI profiles
  custom.aws = {
    enable = true;
    profiles = [
      {
        name = "jbl_root_root";
        credentialProcess = "${jblRootCredProcess}";
      }
    ];
  };
}
