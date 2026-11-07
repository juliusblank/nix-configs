/**
  Restic S3 backup module.

  Installs two commands and, when `automatic` is true, two launchd user agents:
  - `backup-run` — backup of `paths`, then `forget --prune`. The daily agent runs
    it with `--scheduled` at `schedule` (default: 02:00).
  - `backup-check` — structural integrity check; the weekly agent runs it on
    Sunday at 03:00.

  Scheduled runs are skipped while the sentinel file $HOME/.config/backup/paused
  exists (`just backup-pause` / `just backup-resume`); manual runs ignore it. Any
  run is skipped while a process listed in `inhibitApps` is running.

  Secrets are read at runtime: the restic password via `op read`, the AWS keys via
  `aws configure export-credentials` (restic cannot resolve the profile's
  `credential_process` itself). Both need 1Password to be unlocked, so scheduled
  runs fail while the Mac is locked — keep `automatic = false` until that is solved.
*/
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.backup;
  home = config.home.homeDirectory;

  repo = "s3:s3.${cfg.awsRegion}.amazonaws.com/${cfg.bucket}/${cfg.hostPrefix}";

  pathsArray = lib.concatStringsSep "\n  " (map lib.escapeShellArg cfg.paths);
  excludeArgs = lib.concatStringsSep "\n  " (
    map (e: "--exclude=${lib.escapeShellArg e}") cfg.excludes
  );
  inhibitChecks = lib.concatMapStrings (app: ''
    if pgrep -x ${lib.escapeShellArg app} > /dev/null 2>&1; then
      log "backup skipped — ${app} is running"
      exit 0
    fi
  '') cfg.inhibitApps;

  # Shared preamble: logging, restic settings and secrets. Output goes to stdout
  # only — launchd writes it to the agent's log file, a manual run shows it in the
  # terminal. Without a terminal, restic prints a progress line once a minute.
  preamble = ''
    set -euo pipefail

    RESTIC=${pkgs.restic}/bin/restic
    REPO=${repo}

    log() {
      printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
    }

    [[ -t 1 ]] || export RESTIC_PROGRESS_FPS=0.0167

    load_secrets() {
      RESTIC_PASSWORD=$(${pkgs._1password-cli}/bin/op read "op://github_nix-configs/Restic Backup Password/password") || {
        log "ERROR: failed to read backup password from 1Password — is 1Password unlocked?"
        exit 1
      }
      export RESTIC_PASSWORD
      local creds
      creds=$(AWS_CONFIG_FILE=${home}/.aws/config ${pkgs.awscli2}/bin/aws configure export-credentials \
        --profile ${lib.escapeShellArg cfg.awsProfile} --format env) || {
        log "ERROR: could not get AWS credentials for profile ${cfg.awsProfile} — is 1Password unlocked?"
        exit 1
      }
      eval "$creds"
    }
  '';

  backupScript = pkgs.writeShellScriptBin "backup-run" ''
    # Keep the Mac from idle-sleeping for the whole run (lid close still sleeps).
    if [[ -z ''${BACKUP_CAFFEINATED:-} ]]; then
      BACKUP_CAFFEINATED=1 exec /usr/bin/caffeinate -i "$0" "$@"
    fi

    ${preamble}

    if [[ ''${1:-} == --scheduled && -f ${home}/.config/backup/paused ]]; then
      log "backup paused — sentinel file present"
      exit 0
    fi

    ${inhibitChecks}

    load_secrets
    log "starting backup to $REPO"

    paths=(
      ${pathsArray}
    )
    excludes=(
      ${excludeArgs}
    )

    "$RESTIC" --repo "$REPO" backup "''${excludes[@]}" "''${paths[@]}" 2>&1

    log "pruning old snapshots"
    "$RESTIC" --repo "$REPO" forget \
      --keep-last ${toString cfg.keepLast} \
      --keep-monthly ${toString cfg.keepMonthly} \
      --prune \
      2>&1

    log "backup complete"
  '';

  # Weekly structural check — does not download data, so no egress cost.
  # Run `just backup-check` for a 10 % data-sample verification.
  checkScript = pkgs.writeShellScriptBin "backup-check" ''
    ${preamble}

    load_secrets
    log "starting integrity check"
    "$RESTIC" --repo "$REPO" check 2>&1
    log "integrity check complete"
  '';
in
{
  options.custom.backup = {
    enable = lib.mkEnableOption "restic S3 backup";

    bucket = lib.mkOption {
      type = lib.types.str;
      description = "S3 bucket name for the restic repository.";
    };

    hostPrefix = lib.mkOption {
      type = lib.types.str;
      default = "serenity";
      description = "Prefix within the bucket (one per host). Used as the restic repo path.";
    };

    awsRegion = lib.mkOption {
      type = lib.types.str;
      default = "eu-central-1";
      description = "AWS region where the backup bucket lives.";
    };

    awsProfile = lib.mkOption {
      type = lib.types.str;
      default = "personal-nix-configs-infra";
      description = "AWS CLI profile used for S3 access.";
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Absolute paths to include in the backup.";
      example = [
        "/Users/jbl/Music"
        "/Users/jbl/Pictures"
      ];
    };

    excludes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Patterns passed to restic --exclude.";
      example = [
        ".DS_Store"
        "node_modules"
      ];
    };

    inhibitApps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Process names (matched via `pgrep -x`) that prevent the backup from
        running. Use the exact process name as shown by Activity Monitor.
      '';
      example = [
        "rekordbox"
        "djay Pro AI"
      ];
    };

    automatic = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run the daily backup and the weekly check as launchd agents. When false,
        only the `backup-run` / `backup-check` commands are installed.
      '';
    };

    schedule = lib.mkOption {
      type = lib.types.attrs;
      default = {
        Hour = 2;
        Minute = 0;
      };
      description = "launchd StartCalendarInterval for the daily backup agent.";
    };

    keepLast = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Number of most-recent snapshots to keep (passed to restic forget --keep-last).";
    };

    keepMonthly = lib.mkOption {
      type = lib.types.int;
      default = 12;
      description = "Number of monthly snapshots to keep (passed to restic forget --keep-monthly).";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.restic
      backupScript
      checkScript
    ];

    launchd.agents = lib.mkIf cfg.automatic {
      # Daily backup agent — runs at cfg.schedule (default: 02:00).
      "com.juliusblank.backup" = {
        enable = true;
        config = {
          Label = "com.juliusblank.backup";
          ProgramArguments = [
            "${backupScript}/bin/backup-run"
            "--scheduled"
          ];
          StartCalendarInterval = [ cfg.schedule ];
          RunAtLoad = false;
          StandardOutPath = "${home}/Library/Logs/backup.log";
          StandardErrorPath = "${home}/Library/Logs/backup-error.log";
        };
      };

      # Weekly structural integrity check — Sunday at 03:00, no data download.
      "com.juliusblank.backup-check" = {
        enable = true;
        config = {
          Label = "com.juliusblank.backup-check";
          ProgramArguments = [ "${checkScript}/bin/backup-check" ];
          StartCalendarInterval = [
            {
              Weekday = 0;
              Hour = 3;
              Minute = 0;
            }
          ];
          RunAtLoad = false;
          StandardOutPath = "${home}/Library/Logs/backup-check.log";
          StandardErrorPath = "${home}/Library/Logs/backup-check-error.log";
        };
      };
    };
  };
}
