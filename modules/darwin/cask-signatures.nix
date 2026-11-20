{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.caskSignatures;

  /**
    Code requirement that pins an app to an Apple-issued certificate of one team
    (Developer ID Team ID). Gatekeeper accepts any notarized Developer ID; this
    requirement also rejects an app that a different team signed.
  */
  requirement = team: ''anchor apple generic and certificate leaf[subject.OU] = "${team}"'';

  checks = lib.concatStrings (
    lib.mapAttrsToList (app: team: ''
      check ${lib.escapeShellArg app} ${lib.escapeShellArg (requirement team)} ${lib.escapeShellArg team}
    '') cfg.apps
  );

  /**
    `verify-cask-signatures [--deep]` checks every app in `custom.caskSignatures.apps`
    against its pinned Team ID. Without `--deep` only the outer bundle is checked
    (signature, sealed resources, signer; ~10 s for all apps), with `--deep` every
    nested component too (~30 s). `--strict` is not used: it rejects Finder xattrs
    that app updaters leave behind (seen on Google Chrome). Exits 1 if an app is
    missing or fails.
  */
  verifyCaskSignatures = pkgs.writeShellApplication {
    name = "verify-cask-signatures";
    text = ''
      deep=()
      if [[ "''${1:-}" == "--deep" ]]; then deep=(--deep); fi
      failed=0

      check() {
        local app="$1" req="$2" team="$3" err
        if [[ ! -e "$app" ]]; then
          echo "MISSING  $app (expected Team ID $team)"
          failed=1
        elif err=$(/usr/bin/codesign --verify "''${deep[@]}" -R="$req" "$app" 2>&1); then
          echo "ok       $app ($team)"
        else
          echo "FAILED   $app (expected Team ID $team): ''${err##*$'\n'}"
          failed=1
        fi
      }

      ${checks}
      exit "$failed"
    '';
  };
in
{
  options.custom.caskSignatures = {
    enable = lib.mkEnableOption "signer (Team ID) check of Homebrew cask apps after activation";

    apps = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "/Applications/AusweisApp.app" = "G7EQCJU4BR";
      };
      description = ''
        App bundle path → expected Developer ID Team ID (`codesign -dv <app>` →
        `TeamIdentifier`). Apps without a Developer ID signature cannot be listed.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ verifyCaskSignatures ];

    # nix-darwin runs the homebrew step before postActivation, so this sees the casks
    # that this activation installed or upgraded. Warn only: the app is already on
    # disk, and failing the activation would not remove it.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo "checking cask app signatures..." >&2
      if ! out=$(${lib.getExe verifyCaskSignatures}); then
        printf '%s\n' "$out" | grep -v '^ok ' >&2
        echo "WARNING: cask app signature check failed; do not open these apps" \
          "before you have checked them (just verify-apps)" >&2
      fi
    '';
  };
}
