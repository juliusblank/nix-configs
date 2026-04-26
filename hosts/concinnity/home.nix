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

  home.packages = with pkgs; [
    yubikey-manager # `ykman` — AWS_VAULT_PROMPT=ykman (see sessionVariables + initContent)
    aws-vault # AWS credential exec/login (legacy, migration to granted in progress)
    granted # AWS credential manager (SSO, credential-process)
    # credential_process wrapper — fetches IAM keys from 1Password, calls
    # GetSessionToken with YubiKey MFA, caches the session credentials.
    # Usage:  credential_process = op-credential-process "op://vault/item" "arn:aws:iam::…:mfa/user"
    # Without the MFA ARN arg, returns raw IAM keys (no session).
    (writeShellScriptBin "op-credential-process" ''
      set -euo pipefail
      OP="${_1password-cli}/bin/op"
      YKMAN="${yubikey-manager}/bin/ykman"
      AWS="${awscli2}/bin/aws"
      JQ="${jq}/bin/jq"

      item="$1"
      mfa_serial="''${2:-}"

      # Without MFA serial, return raw IAM keys from 1Password.
      if [ -z "$mfa_serial" ]; then
        ak=$($OP read "''${item}/access_key_id")
        sk=$($OP read "''${item}/secret_access_key")
        printf '{"Version":1,"AccessKeyId":"%s","SecretAccessKey":"%s"}' "$ak" "$sk"
        exit 0
      fi

      # With MFA serial, return cached session credentials or create new ones.
      cache_dir="$HOME/.aws/op-mfa-cache"
      cache_key=$(printf '%s' "$item" | shasum -a 256 | cut -c1-16)
      cache_file="$cache_dir/$cache_key.json"
      mkdir -p "$cache_dir"
      chmod 700 "$cache_dir"

      # Check cache: valid if file exists and expiration is in the future.
      if [ -f "$cache_file" ]; then
        expiration=$($JQ -r '.Expiration // empty' "$cache_file" 2>/dev/null || true)
        if [ -n "$expiration" ]; then
          exp_epoch=$(date -jf "%Y-%m-%dT%H:%M:%S+00:00" "$expiration" "+%s" 2>/dev/null \
                   || date -jf "%Y-%m-%dT%H:%M:%SZ" "$expiration" "+%s" 2>/dev/null \
                   || echo 0)
          now_epoch=$(date "+%s")
          # 5-minute buffer before expiry
          if [ "$now_epoch" -lt "$((exp_epoch - 300))" ]; then
            cat "$cache_file"
            exit 0
          fi
        fi
      fi

      # Fetch raw IAM keys from 1Password.
      ak=$($OP read "''${item}/access_key_id")
      sk=$($OP read "''${item}/secret_access_key")

      # Generate TOTP from YubiKey.
      totp=$($YKMAN oath accounts code --single "$mfa_serial")

      # Call GetSessionToken with MFA.
      session=$(AWS_ACCESS_KEY_ID="$ak" AWS_SECRET_ACCESS_KEY="$sk" \
        $AWS sts get-session-token \
          --serial-number "$mfa_serial" \
          --token-code "$totp" \
          --output json)

      # Format as credential_process JSON and cache.
      result=$($JQ -n \
        --arg ak "$(echo "$session" | $JQ -r '.Credentials.AccessKeyId')" \
        --arg sk "$(echo "$session" | $JQ -r '.Credentials.SecretAccessKey')" \
        --arg st "$(echo "$session" | $JQ -r '.Credentials.SessionToken')" \
        --arg ex "$(echo "$session" | $JQ -r '.Credentials.Expiration')" \
        '{Version:1,AccessKeyId:$ak,SecretAccessKey:$sk,SessionToken:$st,Expiration:$ex}')

      printf '%s' "$result" > "$cache_file"
      chmod 600 "$cache_file"
      printf '%s' "$result"
    '')
  ];

  # Granted (config + Firefox) — custom `assume` function below replaces the
  # default alias to auto-inject YubiKey TOTP.
  custom.granted = {
    enable = true;
    assumeShellAlias = false;
  };

  # `assume` wraps granted — MFA is handled by op-credential-process (YubiKey
  # TOTP + session caching), so no --mfa-token needed here.
  # bashcompinit: superuser.com/a/1740258 (CC BY-SA 4.0).
  programs.zsh.initContent = lib.mkAfter ''
    autoload -U +X bashcompinit && bashcompinit

    assume() {
    	if [ -z "$1" ]; then
    		echo "Usage: assume <profile>";
    		return 1;
    	fi;
    	export GRANTED_ALIAS_CONFIGURED=true
    	source ${pkgs.granted}/bin/assume "$@";
    }

    complete -W "$(aws configure list-profiles)" assume
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
