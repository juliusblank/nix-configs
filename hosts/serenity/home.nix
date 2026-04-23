{ pkgs, ... }:

let
  # Reads static IAM credentials from 1Password and emits the JSON format
  # AWS CLI credential_process expects.
  # TODO: replace with `granted credential-process` once SSO is configured.
  jblRootCredProcess = pkgs.writeShellScript "aws-creds-jbl-root" ''
    set -euo pipefail

    op=${pkgs._1password-cli}/bin/op

    read_or_die() {
      local ref=$1
      local result
      if ! result=$("$op" read "$ref" 2>&1); then
        echo "aws-creds-jbl-root: failed to read $ref from 1Password" >&2
        echo "Make sure 1Password is unlocked and the 'nix-configs-infra' item exists in the Private vault." >&2
        exit 1
      fi
      printf '%s' "$result"
    }

    id=$(read_or_die 'op://infrastructure/nix-configs-infra/access_key_id')
    secret=$(read_or_die 'op://infrastructure/nix-configs-infra/secret_access_key')

    exec ${pkgs.jq}/bin/jq -cn \
      --arg id "$id" \
      --arg secret "$secret" \
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
        name = "nix-configs-infra";
        credentialProcess = "${jblRootCredProcess}";
      }
    ];
  };
}
