{ pkgs, ... }:

let
  # The 1Password entry name is the single source of truth — the AWS CLI
  # profile name and op:// references are both derived from it.
  # TODO: replace credentialProcess with `granted credential-process` once SSO is configured.
  opVault = "infrastructure";
  opEntry = "personal-nix-configs-infra";

  credProcess = pkgs.writeShellScript "aws-creds-${opEntry}" ''
    set -euo pipefail

    op=${pkgs._1password-cli}/bin/op

    read_or_die() {
      local ref=$1
      local result
      if ! result=$("$op" read "$ref" 2>&1); then
        echo "aws-creds-${opEntry}: failed to read $ref from 1Password" >&2
        echo "Make sure 1Password is unlocked and '${opEntry}' exists in the ${opVault} vault." >&2
        exit 1
      fi
      printf '%s' "$result"
    }

    id=$(read_or_die 'op://${opVault}/${opEntry}/access_key_id')
    secret=$(read_or_die 'op://${opVault}/${opEntry}/secret_access_key')

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

  # 1Password SSH agent — which keys to expose on this machine
  home.file.".config/1password/ssh/agent.toml".text = ''
    # All SSH keys from the Private vault (includes the personal "serenity" key)
    [[ssh-keys]]
    vault = "Private"

    # Claude Code signing key
    [[ssh-keys]]
    item = "Claude github SSH key"
    vault = "github_nix-configs"
  '';

  # Granted for AWS credential management
  custom.granted.enable = true;

  # AWS CLI profiles
  custom.aws = {
    enable = true;
    profiles = [
      {
        name = opEntry;
        credentialProcess = "${credProcess}";
      }
    ];
  };
}
