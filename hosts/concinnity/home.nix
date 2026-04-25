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
    aws-vault # AWS credential exec/login via vassume/vlogin functions
    granted # AWS credential manager (SSO, credential-process)
  ];

  # Granted (config + Firefox) — `assume` alias goes to granted; aws-vault
  # helpers below use `vassume` / `vlogin` to avoid the name collision.
  # `login` is a granted alias for `assume -c` (open console in browser).
  custom.granted = {
    enable = true;
  };

  # aws-vault 1Password Desktop backend — env vars replace CLI flags.
  programs.zsh.sessionVariables = {
    AWS_VAULT_BACKEND = "op-desktop";
    AWS_VAULT_PROMPT = "ykman";
    AWS_VAULT_OP_VAULT_ID = "7awg3jx7uqzj5z5q33tqx4iv7e";
    AWS_VAULT_OP_DESKTOP_ACCOUNT_ID = "CZFGJNG3BVFZRLCMXWTVVTBPZ4";
  };

  # aws-vault helpers (vassume, vlogin) + granted wrappers (gassume, login).
  # Backend and prompt are configured via sessionVariables above; functions only
  # need PATH for ykman and profile/duration logic.
  # bashcompinit only — home-manager already runs compinit; a second compinit is slow and
  # re-scans fpath. bashcompinit: superuser.com/a/1740258 (CC BY-SA 4.0).
  programs.zsh.initContent = lib.mkAfter ''
    autoload -U +X bashcompinit && bashcompinit

    vassume() {
    	if [ -z "$1" ]; then
    		echo "Usage: vassume <profile>";
    		return 1;
    	fi;

    	profile="$1";
    	duration="8h";

    	if [[ "$profile" == *on-call-engineer-write* ]]; then
    		duration="2h";
    	fi;

    	PATH="${ykmanBinPath}:$PATH" aws-vault exec "$profile" -d "$duration";
    }

    vlogin() {
    	if [ -z "$1" ]; then
    		echo "Usage: vlogin <profile>";
    		return 1;
    	fi;

    	profile="$1";
    	duration="8h";

    	if [[ "$profile" == *on-call-engineer-write* ]]; then
    		duration="2h";
    	fi;

    	PATH="${ykmanBinPath}:$PATH" aws-vault login "$profile" -d "$duration";
    }

    # granted + YubiKey MFA: auto-generate TOTP via ykman and pass to assume.
    gassume() {
    	if [ -z "$1" ]; then
    		echo "Usage: gassume <profile>";
    		return 1;
    	fi;
    	assume "$1" --mfa-token "$("${ykmanBinPath}/ykman" oath accounts code --single arn:aws:iam::685159096301:mfa/julius.blankyubikey)";
    }

    # login = granted console (assume -c): open AWS console in the browser.
    login() { assume -c "$@"; }

    complete -W "$(aws configure list-profiles)" vassume
    complete -W "$(aws configure list-profiles)" vlogin
    complete -W "$(aws configure list-profiles)" gassume
    complete -W "$(aws configure list-profiles)" login
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
