{ pkgs, lib, ... }:

let
  # Work SSH signing — public key from 1Password → "github ssh key" (Private vault).
  # `includes[].contents` uses the same shape as `git-config(5)` / HM `toGitINI` (camelCase keys).
  workGitIdentity = {
    user = {
      name = "Julius Blank";
      email = "julius.blank@taktile.com";
      signingKey = "key::ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwfAJRp8a2KepH2l6HNikRiebYfO6/EYs7OX1eewUfm";
    };
    gpg.format = "ssh";
    commit.gpgSign = true;
  };

  # Nix `yubikey-manager` must win over any Homebrew `ykman` (concinnity prepends brew to system PATH).
  ykmanBinPath = lib.makeBinPath [ pkgs.yubikey-manager ];

  # Granted `assume` shell script — resolved at build time so the zsh `assume`
  # function can `source` it without recursion.
  grantedAssume = "${pkgs.granted}/bin/assume";

  # YubiKey OATH account for AWS MFA (from `ykman oath accounts list`).
  ykOathAccount = "arn:aws:iam::685159096301:mfa/julius.blankyubikey";

  # Reads raw IAM keys from Granted's macOS keychain WITHOUT doing MFA/GetSessionToken.
  # Used as credential_process in ~/.aws/config so that assumego resolves MFA itself
  # (where --mfa-token works). `granted credential-process` can't be used because it
  # does GetSessionToken+MFA in a subprocess that can't receive --mfa-token.
  grantedRawCredProcess = pkgs.writeShellScript "granted-raw-credential-process" ''
    set -euo pipefail
    profile="''${1:?Usage: granted-raw-credential-process <profile>}"
    raw=$(security find-generic-password -s "granted-aws-iam-credentials" -a "$profile" -w 2>/dev/null)
    if [ -z "$raw" ]; then
      echo "granted-raw-credential-process: no credentials for '$profile' in Granted keychain" >&2
      exit 1
    fi
    echo "$raw" | ${pkgs.jq}/bin/jq -c '{
      Version: 1,
      AccessKeyId: .AccessKeyID,
      SecretAccessKey: .SecretAccessKey
    }'
  '';
in
{
  imports = [
    ../../home/common.nix
    ../../home/darwin.nix
    ../../home/modules/granted.nix
  ];

  home.username = "julius.blank";
  home.homeDirectory = "/Users/julius.blank";

  # --- Git identity isolation ---
  #
  # Default identity (personal) comes from common.nix. Canonical clone for this
  # repo on both macOS hosts: ~/github/juliusblank/nix-configs — a sibling of the
  # work tree, so it never matches the includeIf rules below.
  #
  # Work repos: clone under ~/github/taktile-org/ (primary). Legacy ~/work/ kept
  # so old checkouts keep working until moved.
  #
  programs.git.includes = [
    {
      condition = "gitdir:~/github/taktile-org/";
      contents = workGitIdentity;
    }
    {
      condition = "gitdir:~/work/";
      contents = workGitIdentity;
    }
  ];

  # --- 1Password SSH agent ---
  #
  # Controls which SSH keys the 1Password agent exposes to this machine.
  # Keys are referenced by item name + vault. The agent serves the private
  # key to SSH/git; only the item name is configured here (no secrets).
  #
  # Isolation model:
  #   - "github ssh key" (Private vault) → work GitHub access + commit signing
  #   - "serenity" (Private vault) → personal repos (nix-configs, blog, etc.)
  #
  # Repos that should NOT be accessible from the work machine (DJ tooling,
  # purely private projects) should use a different SSH key that is not
  # listed here.
  home.file.".config/1password/ssh/agent.toml".text = ''
    # Work SSH key — used for work GitHub repos and commit signing
    [[ssh-keys]]
    item = "github ssh key"
    vault = "Private"

    # Personal SSH key — grants access to personal repos that are useful
    # in a work context (nix-configs, blog, etc.)
    [[ssh-keys]]
    item = "serenity"
    vault = "Private"
  '';

  # Stable path for credential_process in ~/.aws/config:
  #   credential_process = /Users/julius.blank/.granted/raw-credential-process tktliam
  home.file.".granted/raw-credential-process".source = grantedRawCredProcess;

  home.packages = with pkgs; [
    yubikey-manager # `ykman` for YubiKey TOTP in assume/assume-vault (see zsh initContent below)
    aws-vault # legacy: assume-vault / login-vault functions
    granted # primary: assume / login functions (SSO, credential-process)
  ];

  # Granted (config + Firefox) — assumeShellAlias is off because we define a custom
  # `assume` function with YubiKey TOTP integration (see initContent below).
  # Browser set explicitly: Firefox is installed outside home-manager on concinnity.
  custom.granted = {
    enable = true;
    assumeShellAlias = false;
    defaultBrowser = "FIREFOX";
    customBrowserPath = "/Applications/Firefox.app";
  };

  # AWS assume/login helpers + bash-style `complete` for profile names.
  # bashcompinit only — home-manager already runs compinit; a second compinit is slow and
  # re-scans fpath. bashcompinit: superuser.com/a/1740258 (CC BY-SA 4.0).
  #
  # Two paths:
  #   assume / login        — Granted (primary), YubiKey TOTP via --mfa-token
  #   assume-vault / login-vault — aws-vault (legacy), --prompt ykman
  programs.zsh.initContent = lib.mkAfter ''
    autoload -U +X bashcompinit && bashcompinit

    # --- Granted (primary) ---

    assume() {
      if [ -z "$1" ]; then
        echo "Usage: assume <profile>"
        return 1
      fi

      local profile="$1"
      shift

      local token
      token=$(PATH="${ykmanBinPath}:$PATH" ykman oath accounts code -s "${ykOathAccount}")

      # GRANTED_ALIAS_CONFIGURED tells assumego to skip the "install alias" prompt.
      # The assume script's own detection doesn't fire in zsh when sourced from a
      # function (zsh sets $0 to the script path, defeating the bash-style checks).
      export GRANTED_ALIAS_CONFIGURED=true
      if [[ -n "$token" ]]; then
        source "${grantedAssume}" "$profile" --mfa-token "$token" "$@"
      else
        echo "[!] YubiKey TOTP failed — Granted will prompt for MFA" >&2
        source "${grantedAssume}" "$profile" "$@"
      fi
    }

    login() {
      if [ -z "$1" ]; then
        echo "Usage: login <profile>"
        return 1
      fi

      local profile="$1"
      shift

      export GRANTED_ALIAS_CONFIGURED=true
      source "${grantedAssume}" "$profile" --console "$@"
    }

    # --- aws-vault (legacy) ---

    assume-vault() {
      if [ -z "$1" ]; then
        echo "Usage: assume-vault <profile>"
        return 1
      fi

      local profile="$1"
      local duration="8h"

      if [[ "$profile" == *on-call-engineer-write* ]]; then
        duration="2h"
      fi

      PATH="${ykmanBinPath}:$PATH" aws-vault exec --prompt ykman "$profile" -d "$duration"
    }

    login-vault() {
      if [ -z "$1" ]; then
        echo "Usage: login-vault <profile>"
        return 1
      fi

      local profile="$1"
      local duration="8h"

      if [[ "$profile" == *on-call-engineer-write* ]]; then
        duration="2h"
      fi

      PATH="${ykmanBinPath}:$PATH" aws-vault login --prompt ykman "$profile" -d "$duration"
    }

    complete -W "$(aws configure list-profiles)" assume assume-vault login login-vault
  '';

  # Work signing key for `git log --show-signature` (append to global allowed_signers from common.nix).
  custom.extraAllowedSigners = ''
    julius.blank@taktile.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwfAJRp8a2KepH2l6HNikRiebYfO6/EYs7OX1eewUfm
  '';

  # ~/.aws/config is manually managed on concinnity — generated by the
  # taktile-infra generate-aws-config workflow, then copied into place.
  # Do not enable custom.aws here; it overwrites the file on every activation.
  # See docs/SPEC.md #22.
}
