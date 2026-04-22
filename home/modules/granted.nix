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

    # Declarative granted config — macOS keychain is the default credential store
    home.file.".granted/config".text =
      lib.concatStringsSep "\n"
        (
          [
            ''Ordering = "Frecency"''
            "DefaultExportAllEnvVar = true"
          ]
          ++ lib.optional firefoxEnabled ''DefaultBrowser = "FIREFOX"''
        )
      + "\n";

    # Add Granted Firefox extension when Firefox is enabled
    programs.firefox.profiles.default.extensions.packages = lib.mkIf firefoxEnabled (
      with pkgs.nur.repos.rycee.firefox-addons; [ granted ]
    );
  };
}
