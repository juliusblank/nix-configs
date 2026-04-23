{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.granted;
  firefoxEnabled = config.programs.firefox.enable;
in
{
  options.custom.granted = {
    enable = lib.mkEnableOption "Granted AWS credential manager";
  };

  config = lib.mkIf cfg.enable {
    # Granted requires the alias in ~/.zshenv (not ~/.zshrc) so it can detect
    # it as already installed and skip the interactive setup prompt.
    programs.zsh.envExtra = ''
      alias assume="source assume"
    '';

    # Shell completion
    programs.zsh.initContent = lib.mkAfter ''
      if command -v granted &>/dev/null; then
        eval "$(granted completion --shell zsh)"
      fi
    '';

    # Granted opens its config for writing on startup, so home.file (read-only symlink) won't work.
    # Instead, copy a nix-generated file each activation so settings are declarative but the file
    # remains writable.
    home.activation.grantedConfig =
      let
        configFile = pkgs.writeText "granted-config" ''
          Ordering = "Frecency"

          # Export all AWS credential env vars by default (AWS_ACCESS_KEY_ID etc.)
          DefaultExportAllEnvVar = true

          # Use OAuth PKCE flow for SSO login — skips manual device-code entry,
          # redirects straight back from the browser. Requires a local browser.
          UseAuthorizationCode = false

          # Re-authenticate automatically when the SSO token expires.
          # Safe on a personal machine; do not enable on headless systems.
          CredentialProcessAutoLogin = false

          # Suppress "assume this profile again later" usage hints.
          DisableUsageTips = false
          ${lib.optionalString firefoxEnabled ''
            DefaultBrowser = "FIREFOX"
            # Nix store path — kept current on every home-manager switch
            CustomBrowserPath = "${pkgs.firefox}/Applications/Firefox.app"
          ''}
        '';
      in
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$HOME/.granted"
        install -m 644 ${configFile} "$HOME/.granted/config"
      '';

    # Add Granted Firefox extension when Firefox is enabled
    programs.firefox.profiles.default.extensions.packages = lib.mkIf firefoxEnabled (
      with pkgs.nur.repos.rycee.firefox-addons; [ granted ]
    );
  };
}
