{ pkgs, lib, ... }:

let
  # Work SSH signing — public key from 1Password → "github ssh key" (Employee vault).
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

  home = {
    username = "julius.blank";
    homeDirectory = "/Users/julius.blank";

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
    file.".config/1password/ssh/agent.toml".text = ''
      # Work SSH key — used for cloning/pushing work GitHub repos and for signing
      # commits made under ~/github/taktile-org/, ~/github/jbl-taktile/ and ~/work/
      # (via workGitIdentity below).
      [[ssh-keys]]
      item = "github ssh key"
      vault = "Employee"

      # Personal signing key dedicated to this host — signs every non-work commit
      # authored as dev@juliusblank.de. Registered as a signing key on juliusblank's
      # GitHub account; private key never leaves 1Password.
      [[ssh-keys]]
      item = "concinnity signing key"
      vault = "Employee"
    '';

    packages = with pkgs; [
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
  };

  programs = {
    # --- Git identity isolation ---
    #
    # Default identity (personal) comes from common.nix. Canonical clone for this
    # repo on both macOS hosts: ~/github/juliusblank/nix-configs — a sibling of the
    # work tree, so it never matches the includeIf rules below.
    #
    # Work repos:
    #   - ~/github/taktile-org/ — org-owned work repos (primary).
    #   - ~/github/jbl-taktile/ — personal-but-work-owned repos under the jbl-taktile
    #     GitHub user (e.g. the Claude Code plugin marketplace jbl-personal lives at
    #     ~/github/jbl-taktile/claude-skills). The owner is a work GitHub account, so
    #     commits must author + sign as work, same as taktile-org/*. The signing key
    #     (`workGitIdentity.user.signingKey`) is the same 1Password-served "github
    #     ssh key" already registered on the jbl-taktile GitHub account for auth; add
    #     it there a second time as a Signing key for GitHub to verify these commits.
    #   - ~/work/ — legacy path, kept so old checkouts keep working until moved.
    git = {
      includes = [
        {
          condition = "gitdir:~/github/taktile-org/";
          contents = workGitIdentity;
        }
        {
          condition = "gitdir:~/github/jbl-taktile/";
          contents = workGitIdentity;
        }
        {
          condition = "gitdir:~/work/";
          contents = workGitIdentity;
        }
      ];

      # Default signing key for commits on this host — a personal SSH key dedicated
      # to concinnity. Served by 1Password (`concinnity signing key` in Employee vault)
      # and registered as a signing key on juliusblank's GitHub account. The work key
      # from above still signs commits under ~/github/taktile-org/ and ~/work/ via
      # `workGitIdentity.user.signingKey`.
      signing.key = "key::ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICqzDzUYBHkpAe0EURy0G91tZMiUcoZAO4qjmBy/fbRQ";

      # Trust the corporate root CA that Aikido Security's endpoint protection
      # uses to inspect outbound HTTPS. Required for git-over-HTTPS on this host;
      # SSH-only remotes are unaffected. Path is stable per Aikido's install layout.
      settings.http.sslCAInfo = "/Library/Application Support/AikidoSecurity/EndpointProtection/run/endpoint-protection-openssl-combined-ca.pem";
    };

    # Firefox with container tabs for multi-account AWS console access.
    # multi-account-containers: named containers per AWS account.
    # open-url-in-container: handles ext+container: protocol from `login` function.
    # granted: Granted AWS extension for console session management.
    firefox = {
      enable = true;
      profiles.default = {
        isDefault = true;
        extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
          multi-account-containers
          open-url-in-container
        ];
      };
    };

    zsh = {
      # aws-vault 1Password Desktop backend.
      sessionVariables = {
        AWS_VAULT_BACKEND = "op-desktop";
        AWS_VAULT_PROMPT = "ykman";
        AWS_VAULT_OP_VAULT_ID = "7awg3jx7uqzj5z5q33tqx4iv7e";
        AWS_VAULT_OP_DESKTOP_ACCOUNT_ID = "CZFGJNG3BVFZRLCMXWTVVTBPZ4";
      };

      # Shell functions: assume/login (aws-vault), grassume (granted).
      # bashcompinit: superuser.com/a/1740258 (CC BY-SA 4.0).
      initContent = lib.mkAfter ''
        autoload -U +X bashcompinit && bashcompinit

        # assume <profile>              — start an interactive subshell with
        #                                 the profile's credentials.
        # assume <profile> -- CMD ARGS… — run CMD under the profile and exit
        #                                 (used by `zse -a` to launch Zellij
        #                                 inside an aws-vault subshell).
        assume() {
        	if [ -z "$1" ]; then
        		echo "Usage: assume <profile> [-- CMD ARGS...]";
        		return 1;
        	fi;
        	local profile="$1" duration="8h"
        	shift
        	[[ "$profile" == *on-call-engineer-write* ]] && duration="2h"
        	if [[ "''${1:-}" == "--" ]]; then
        		shift
        		PATH="${ykmanBinPath}:$PATH" aws-vault exec "$profile" -d "$duration" -- "$@"
        	else
        		PATH="${ykmanBinPath}:$PATH" aws-vault exec "$profile" -d "$duration"
        	fi
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
        	# Use the exact bundle path so LaunchServices does not resolve `Firefox`
        	# to a stale nix-store bundle retained by an older system generation.
        	open -a "${pkgs.firefox}/Applications/Firefox.app" "ext+container:name=''${profile}&url=''${url_escaped}"
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

        # daily-tasks capture: `todo "…"` runs /todo headlessly against the local vault.
        # Repo: ~/github/jbl-taktile/daily-tasks. See its CLAUDE.md and spec/SPEC.md.
        # concinnity-only — the vault path is a work tree.
        todo() { (cd "$HOME/github/jbl-taktile/daily-tasks" && claude -p "/todo $*"); }
      '';
    };
  };

  # Granted config (Firefox browser, usage tips, etc.) — grassume uses granted.
  custom.granted = {
    enable = true;
    assumeShellAlias = false;
  };

  # Work signing key for `git log --show-signature` (append to global allowed_signers from common.nix).
  custom.extraAllowedSigners = ''
    julius.blank@taktile.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwfAJRp8a2KepH2l6HNikRiebYfO6/EYs7OX1eewUfm
  '';

  # Claude Code: Taktile skill marketplace + plugins + sandbox allowlist.
  # Equivalent to:
  #   claude plugin marketplace add taktile-org/taktile-skills
  #   claude plugin install tktl-eng-data tktl-eng-frontend
  #   edit ~/.claude/settings.json → add "sandbox.excludedCommands": ["gh", "aws"]
  # Claude Code writes to settings.json at runtime (/config, /model), so home.file
  # (read-only symlink) won't work. Deep-merge only these keys each activation; all other
  # settings are preserved. Claude Code installs enabled plugins on next startup.
  #
  # `sandbox.excludedCommands`: run these tools outside the Claude Code sandbox.
  # - `gh`: TLS verification needs the macOS trust service (trustd), which the
  #   sandbox blocks by default — breaks Go-based tools like `gh` with an opaque
  #   `x509: OSStatus -26276` error.
  # - `aws`: same TLS story (Go-based AWS CLI v2 reaches STS/IAM endpoints), and
  #   ticket / review sessions routinely want `aws sts get-caller-identity`,
  #   `aws s3 ...`, etc. without a per-command permission prompt.
  # The excluded commands still go through Claude Code's normal permission
  # prompt — they just skip the sandbox wrapper.
  home.activation.claudePlugins =
    let
      pluginSettings = pkgs.writeText "claude-plugin-settings.json" (
        builtins.toJSON {
          extraKnownMarketplaces.taktile-skills.source = {
            source = "github";
            repo = "taktile-org/taktile-skills";
          };
          enabledPlugins = {
            "tktl-eng-data@taktile-skills" = true;
            "tktl-eng-frontend@taktile-skills" = true;
          };
          sandbox.excludedCommands = [
            "gh"
            "aws"
          ];
        }
      );
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings="$HOME/.claude/settings.json"
      mkdir -p "$HOME/.claude"
      [ -s "$settings" ] || echo '{}' > "$settings"
      tmp=$(mktemp)
      ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$settings" ${pluginSettings} > "$tmp"
      cat "$tmp" > "$settings" && rm "$tmp"
    '';

  # ~/.aws/config is manually managed on concinnity — generated by the
  # taktile-infra generate-aws-config workflow, then copied into place.
  # Do not enable custom.aws here; it overwrites the file on every activation.
  # See docs/SPEC.md #22.
}
