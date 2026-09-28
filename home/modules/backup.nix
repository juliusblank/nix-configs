/**
  Restic S3 backup module.

  Declares two launchd user agents:
  - Daily backup at the configured schedule (default: 02:00)
  - Weekly structural integrity check (Sunday 03:00)

  Backup runs are inhibited by a sentinel file ($HOME/.config/backup/paused)
  or when any process listed in `inhibitApps` is running. Use `just backup-pause`
  and `just backup-resume` to toggle the sentinel.

  The restic password is read from 1Password at runtime via `op read`.
  AWS credentials come from the host's `custom.aws` credential_process — no
  secrets are stored on disk.
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

  backupScript = pkgs.writeShellScript "backup-run" ''
    set -euo pipefail

    RESTIC=${pkgs.restic}/bin/restic
    OP=${pkgs._1password-cli}/bin/op
    LOG=${home}/Library/Logs/backup.log
    REPO=${repo}

    log() {
      printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$LOG"
    }

    if [[ -f ${home}/.config/backup/paused ]]; then
      log "backup paused — sentinel file present"
      exit 0
    fi

    ${inhibitChecks}

    RESTIC_PASSWORD=$("$OP" read "op://github_nix-configs/Restic Backup Password/password") || {
      log "ERROR: failed to read backup password from 1Password — is 1Password unlocked?"
      exit 1
    }
    export RESTIC_PASSWORD
    export AWS_CONFIG_FILE=${home}/.aws/config
    export AWS_PROFILE=${cfg.awsProfile}

    log "starting backup to $REPO"

    paths=(
      ${pathsArray}
    )
    excludes=(
      ${excludeArgs}
    )

    "$RESTIC" --repo "$REPO" backup "''${excludes[@]}" "''${paths[@]}" \
      2>&1 | tee -a "$LOG"

    log "pruning old snapshots"
    "$RESTIC" --repo "$REPO" forget \
      --keep-last ${toString cfg.keepLast} \
      --keep-monthly ${toString cfg.keepMonthly} \
      --prune \
      2>&1 | tee -a "$LOG"

    log "backup complete"
  '';

  # Weekly structural check — does not download data, so no egress cost.
  # Run `just backup-check` for a 10 % data-sample verification.
  checkScript = pkgs.writeShellScript "backup-check" ''
    set -euo pipefail

    RESTIC=${pkgs.restic}/bin/restic
    OP=${pkgs._1password-cli}/bin/op
    LOG=${home}/Library/Logs/backup-check.log
    REPO=${repo}

    log() {
      printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$LOG"
    }

    RESTIC_PASSWORD=$("$OP" read "op://github_nix-configs/Restic Backup Password/password") || {
      log "ERROR: failed to read backup password from 1Password"
      exit 1
    }
    export RESTIC_PASSWORD
    export AWS_CONFIG_FILE=${home}/.aws/config
    export AWS_PROFILE=${cfg.awsProfile}

    log "starting integrity check"
    "$RESTIC" --repo "$REPO" check 2>&1 | tee -a "$LOG"
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
    home.packages = [ pkgs.restic ];

    launchd.agents = {
      # Daily backup agent — runs at cfg.schedule (default: 02:00).
      "com.juliusblank.backup" = {
        enable = true;
        config = {
          Label = "com.juliusblank.backup";
          ProgramArguments = [ "${backupScript}" ];
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
          ProgramArguments = [ "${checkScript}" ];
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
