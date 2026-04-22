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
    # Shell alias — required for assume to export creds into current shell
    programs.zsh.shellAliases.assume = "source assume";

    # Shell completion
    programs.zsh.initContent = lib.mkAfter ''
      if command -v granted &>/dev/null; then
        eval "$(granted completion zsh)"
      fi
    '';

    # Seed granted config as a regular writable file if it doesn't exist yet.
    # Granted writes to this file at runtime, so home.file (read-only symlink) won't work.
    home.activation.grantedConfig =
      let
        configContent = lib.concatStringsSep "\n" (
          [
            ''Ordering = "Frecency"''
            "DefaultExportAllEnvVar = true"
          ]
          ++ lib.optional firefoxEnabled ''DefaultBrowser = "FIREFOX"''
        );
      in
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -f "$HOME/.granted/config" ]; then
          mkdir -p "$HOME/.granted"
          printf '%s\n' ${lib.escapeShellArg configContent} > "$HOME/.granted/config"
        fi
      '';

    # Add Granted Firefox extension when Firefox is enabled
    programs.firefox.profiles.default.extensions.packages = lib.mkIf firefoxEnabled (
      with pkgs.nur.repos.rycee.firefox-addons; [ granted ]
    );
  };
}
