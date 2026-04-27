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
    yubikey-manager # `ykman` — TOTP generation inside op-credential-process
    granted # AWS credential manager (SSO, credential-process)
    # credential_process wrapper — fetches IAM keys from 1Password, calls
    # GetSessionToken with YubiKey MFA, caches session credentials in 1Password.
    # Usage:  credential_process = op-credential-process "op://vault/item" "arn:aws:iam::…:mfa/user"
    # Without the MFA ARN arg, returns raw IAM keys (no session).
    # Session cache: stored as 1Password item "session-<item-name>" in the same vault.
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

      # Derive vault and cache item name from the op:// URI.
      vault=$(echo "$item" | sed 's|op://\([^/]*\)/.*|\1|')
      item_name=$(echo "$item" | sed 's|op://[^/]*/||')
      cache_item="session-''${item_name}"

      # Check 1Password cache: valid if item exists and Expiration is in the future.
      expiration=$($OP read "op://''${vault}/''${cache_item}/Expiration" 2>/dev/null || true)
      if [ -n "$expiration" ]; then
        # GNU date (-d) or BSD date (-jf); credential_process may run inside
        # a nix devShell where date is GNU coreutils.
        exp_epoch=$(date -d "$expiration" "+%s" 2>/dev/null \
                 || date -jf "%Y-%m-%dT%H:%M:%S%z" "$expiration" "+%s" 2>/dev/null \
                 || echo 0)
        now_epoch=$(date "+%s")
        # 5-minute buffer before expiry
        if [ "$now_epoch" -lt "$((exp_epoch - 300))" ]; then
          ak=$($OP read "op://''${vault}/''${cache_item}/AccessKeyId")
          sk=$($OP read "op://''${vault}/''${cache_item}/SecretAccessKey")
          st=$($OP read "op://''${vault}/''${cache_item}/SessionToken")
          $JQ -n --arg ak "$ak" --arg sk "$sk" --arg st "$st" --arg ex "$expiration" \
            '{Version:1,AccessKeyId:$ak,SecretAccessKey:$sk,SessionToken:$st,Expiration:$ex}'
          exit 0
        fi
      fi

      # Fetch raw IAM keys from 1Password.
      ak=$($OP read "''${item}/access_key_id")
      sk=$($OP read "''${item}/secret_access_key")

      # Generate TOTP from YubiKey.
      totp=$($YKMAN oath accounts code --single "$mfa_serial")

      # Call GetSessionToken with MFA.  Unset stale env vars so credentials
      # from a previous `assume` don't leak into the STS call.
      unset AWS_SESSION_TOKEN AWS_PROFILE AWS_DEFAULT_PROFILE AWS_CREDENTIAL_EXPIRATION 2>/dev/null || true
      session=$(AWS_ACCESS_KEY_ID="$ak" AWS_SECRET_ACCESS_KEY="$sk" \
        $AWS sts get-session-token \
          --serial-number "$mfa_serial" \
          --token-code "$totp" \
          --output json)

      # Extract session credentials.
      s_ak=$(echo "$session" | $JQ -r '.Credentials.AccessKeyId')
      s_sk=$(echo "$session" | $JQ -r '.Credentials.SecretAccessKey')
      s_st=$(echo "$session" | $JQ -r '.Credentials.SessionToken')
      s_ex=$(echo "$session" | $JQ -r '.Credentials.Expiration')

      # Cache in 1Password: create or update the session item.
      if $OP item get "$cache_item" --vault "$vault" >/dev/null 2>&1; then
        $OP item edit "$cache_item" --vault "$vault" \
          "AccessKeyId[text]=$s_ak" \
          "SecretAccessKey[password]=$s_sk" \
          "SessionToken[password]=$s_st" \
          "Expiration[text]=$s_ex" >/dev/null
      else
        $OP item create --vault "$vault" --category "API Credential" \
          --title "$cache_item" \
          "AccessKeyId[text]=$s_ak" \
          "SecretAccessKey[password]=$s_sk" \
          "SessionToken[password]=$s_st" \
          "Expiration[text]=$s_ex" >/dev/null
      fi

      # Return credential_process JSON.
      $JQ -n --arg ak "$s_ak" --arg sk "$s_sk" --arg st "$s_st" --arg ex "$s_ex" \
        '{Version:1,AccessKeyId:$ak,SecretAccessKey:$sk,SessionToken:$st,Expiration:$ex}'
    '')
  ];

  # Granted (config + Firefox) — custom `assume` function below replaces the
  # default alias to auto-inject YubiKey TOTP.
  custom.granted = {
    enable = true;
    assumeShellAlias = false;
  };

  # `assume` calls assumego directly (not the granted shell wrapper) to avoid
  # a phantom YubiKey touch from the wrapper's source-detection logic.
  # MFA is handled by op-credential-process (YubiKey TOTP + session caching).
  # bashcompinit: superuser.com/a/1740258 (CC BY-SA 4.0).
  programs.zsh.initContent = lib.mkAfter ''
    autoload -U +X bashcompinit && bashcompinit

    assume() {
    	if [ -z "$1" ]; then
    		echo "Usage: assume <profile>";
    		return 1;
    	fi;

    	export GRANTED_ALIAS_CONFIGURED=true
    	local _out _ret flag v1 v2 v3 v4 v5 v6 _rest
    	_out=$(${pkgs.granted}/bin/assumego "$@")
    	_ret=$?
    	unset GRANTED_ALIAS_CONFIGURED
    	IFS=' ' read -r flag v1 v2 v3 v4 v5 v6 _rest <<< "$_out"

    	if [[ "$flag" == Granted@(A|De)sume ]]; then
    		unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN \
    		      AWS_PROFILE AWS_REGION AWS_DEFAULT_REGION \
    		      AWS_SESSION_EXPIRATION AWS_CREDENTIAL_EXPIRATION
    	fi
    	if [ "$flag" = "GrantedAssume" ]; then
    		[ "$v1" != "None" ] && export AWS_ACCESS_KEY_ID="$v1"
    		[ "$v2" != "None" ] && export AWS_SECRET_ACCESS_KEY="$v2"
    		[ "$v3" != "None" ] && export AWS_SESSION_TOKEN="$v3"
    		[ "$v4" != "None" ] && export AWS_PROFILE="$v4"
    		[ "$v5" != "None" ] && export AWS_REGION="$v5" AWS_DEFAULT_REGION="$v5"
    		[ "$v6" != "None" ] && export AWS_SESSION_EXPIRATION="$v6" AWS_CREDENTIAL_EXPIRATION="$v6"
    	fi
    	return $_ret
    }

    # Lazy completion: resolve profile names on first tab, not at shell init (~300ms).
    _assume_completions() {
    	reply=(''${(f)"$(${pkgs.awscli2}/bin/aws configure list-profiles 2>/dev/null)"})
    }
    compctl -K _assume_completions assume
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
