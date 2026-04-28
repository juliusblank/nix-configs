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

  # Firefox with container tabs for multi-account AWS console access.
  # multi-account-containers: named containers per AWS account.
  # open-url-in-container: handles ext+container: protocol from `login` function.
  # granted: Granted AWS extension for console session management.
  programs.firefox = {
    enable = true;
    profiles.default = {
      isDefault = true;
      extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
        multi-account-containers
        open-url-in-container
      ];
    };
  };

  home.packages = with pkgs; [
    yubikey-manager # `ykman` — MFA prompt for aws-vault and granted
    aws-vault # AWS credential exec/login with 1Password Desktop backend
    granted # AWS credential manager (SSO, credential-process) — used via grassume
    # credential_process wrapper for granted — fetches IAM keys from 1Password,
    # calls GetSessionToken with YubiKey MFA, caches session in 1Password.
    # Usage:  credential_process = op-credential-process op://vault/item arn:aws:iam::…:mfa/user
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

      # Helper: extract a field from op item JSON by label.
      _op_field() { echo "$1" | $JQ -r --arg l "$2" '.fields[] | select(.label==$l) | .value // empty'; }

      # Check 1Password cache: single op call, extract all fields with jq.
      cached=$($OP item get "$cache_item" --vault "$vault" --format json 2>/dev/null || true)
      if [ -n "$cached" ]; then
        expiration=$(_op_field "$cached" "Expiration")
        if [ -n "$expiration" ]; then
          exp_epoch=$(date -d "$expiration" "+%s" 2>/dev/null \
                   || date -jf "%Y-%m-%dT%H:%M:%S%z" "$expiration" "+%s" 2>/dev/null \
                   || echo 0)
          now_epoch=$(date "+%s")
          if [ "$now_epoch" -lt "$((exp_epoch - 300))" ]; then
            $JQ -n \
              --arg ak "$(_op_field "$cached" "AccessKeyId")" \
              --arg sk "$(_op_field "$cached" "SecretAccessKey")" \
              --arg st "$(_op_field "$cached" "SessionToken")" \
              --arg ex "$expiration" \
              '{Version:1,AccessKeyId:$ak,SecretAccessKey:$sk,SessionToken:$st,Expiration:$ex}'
            exit 0
          fi
        fi
      fi

      # Fetch raw IAM keys from 1Password (single call).
      raw=$($OP item get "$item_name" --vault "$vault" --format json)
      ak=$(_op_field "$raw" "access_key_id")
      sk=$(_op_field "$raw" "secret_access_key")

      # Generate TOTP from YubiKey.
      totp=$($YKMAN oath accounts code --single "$mfa_serial")

      # Call GetSessionToken with MFA.
      unset AWS_SESSION_TOKEN AWS_PROFILE AWS_DEFAULT_PROFILE AWS_CREDENTIAL_EXPIRATION 2>/dev/null || true
      session=$(AWS_ACCESS_KEY_ID="$ak" AWS_SECRET_ACCESS_KEY="$sk" \
        $AWS sts get-session-token \
          --serial-number "$mfa_serial" \
          --token-code "$totp" \
          --output json)

      s_ak=$(echo "$session" | $JQ -r '.Credentials.AccessKeyId')
      s_sk=$(echo "$session" | $JQ -r '.Credentials.SecretAccessKey')
      s_st=$(echo "$session" | $JQ -r '.Credentials.SessionToken')
      s_ex=$(echo "$session" | $JQ -r '.Credentials.Expiration')

      # Cache in 1Password.
      if [ -n "$cached" ]; then
        $OP item edit "$cache_item" --vault "$vault" \
          "AccessKeyId[text]=$s_ak" "SecretAccessKey[password]=$s_sk" \
          "SessionToken[password]=$s_st" "Expiration[text]=$s_ex" >/dev/null
      else
        $OP item create --vault "$vault" --category "API Credential" \
          --title "$cache_item" \
          "AccessKeyId[text]=$s_ak" "SecretAccessKey[password]=$s_sk" \
          "SessionToken[password]=$s_st" "Expiration[text]=$s_ex" >/dev/null
      fi

      $JQ -n --arg ak "$s_ak" --arg sk "$s_sk" --arg st "$s_st" --arg ex "$s_ex" \
        '{Version:1,AccessKeyId:$ak,SecretAccessKey:$sk,SessionToken:$st,Expiration:$ex}'
    '')
  ];

  # Granted config (Firefox browser, usage tips, etc.) — grassume uses granted.
  custom.granted = {
    enable = true;
    assumeShellAlias = false;
  };

  # aws-vault 1Password Desktop backend.
  programs.zsh.sessionVariables = {
    AWS_VAULT_BACKEND = "op-desktop";
    AWS_VAULT_PROMPT = "ykman";
    AWS_VAULT_OP_VAULT_ID = "7awg3jx7uqzj5z5q33tqx4iv7e";
    AWS_VAULT_OP_DESKTOP_ACCOUNT_ID = "CZFGJNG3BVFZRLCMXWTVVTBPZ4";
  };

  # Shell functions: assume/login (aws-vault), grassume (granted).
  # bashcompinit: superuser.com/a/1740258 (CC BY-SA 4.0).
  programs.zsh.initContent = lib.mkAfter ''
    autoload -U +X bashcompinit && bashcompinit

    assume() {
    	if [ -z "$1" ]; then
    		echo "Usage: assume <profile>";
    		return 1;
    	fi;
    	local profile="$1" duration="8h"
    	[[ "$profile" == *on-call-engineer-write* ]] && duration="2h"
    	PATH="${ykmanBinPath}:$PATH" aws-vault exec "$profile" -d "$duration"
    }

    login() {
    	if [ -z "$1" ]; then
    		echo "Usage: login <profile>";
    		return 1;
    	fi;
    	local profile="$1" duration="8h"
    	[[ "$profile" == *on-call-engineer-write* ]] && duration="2h"
    	local url
    	url=$(PATH="${ykmanBinPath}:$PATH" aws-vault login "$profile" -d "$duration" -s)
    	local url_escaped=''${url//&/%26}
    	open -a Firefox "ext+container:name=''${profile}&url=''${url_escaped}"
    }

    # grassume: granted via assumego — for profiles using op-credential-process.
    grassume() {
    	if [ -z "$1" ]; then
    		echo "Usage: grassume <profile>";
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

    # Lazy completion: resolve profile names on first tab, not at shell init.
    _aws_profile_completions() {
    	reply=(''${(f)"$(${pkgs.awscli2}/bin/aws configure list-profiles 2>/dev/null)"})
    }
    compctl -K _aws_profile_completions assume login grassume
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
