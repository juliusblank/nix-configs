/**
  Restic S3 backup module.

  Installs two commands and, when `automatic` is true, two launchd user agents:
  - `backup-run [--scheduled] [group…]` — one `restic backup --tag <group>` per
    group of `sets` (all groups when none is named), then one
    `forget --group-by host,tags --prune`, so each group keeps its own snapshot
    series; snapshots tagged `baseline` are kept forever. The daily agent runs it
    with `--scheduled` at `schedule` (default: 02:00).
  - `backup-check` — structural integrity check; the weekly agent runs it on
    Sunday at 03:00.

  Scheduled runs are skipped while the sentinel file $HOME/.config/backup/paused
  exists (`just backup-pause` / `just backup-resume`); manual runs ignore it. A
  group is skipped while a process listed in its `inhibitApps` is running; the
  other groups still run.

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

  groupNames = lib.attrNames cfg.sets;

  excludeArgs = lib.concatStringsSep "\n  " (
    map (e: "--exclude=${lib.escapeShellArg e}") cfg.excludes
  );

  # Two shell functions per group: `inhibitor_<group>` prints the first running
  # inhibit app (status 1 when none runs); `backup_group_<group>` backs up the
  # group's paths, tagged with the group name, and returns restic's exit code.
  groupFunctions = lib.concatStrings (
    lib.mapAttrsToList (name: set: ''
      inhibitor_${name}() {
        local app
        for app in ${lib.escapeShellArgs set.inhibitApps}; do
          if pgrep -x "$app" > /dev/null 2>&1; then
            printf '%s' "$app"
            return 0
          fi
        done
        return 1
      }
      backup_group_${name}() {
        local paths=(${lib.escapeShellArgs set.paths})
        "$RESTIC" --repo "$REPO" backup --tag ${name} "''${excludes[@]}" "''${paths[@]}" 2>&1
      }
    '') cfg.sets
  );

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

    scheduled=false
    if [[ ''${1:-} == --scheduled ]]; then
      scheduled=true
      shift
    fi

    if $scheduled && [[ -f ${home}/.config/backup/paused ]]; then
      log "backup paused — sentinel file present"
      exit 0
    fi

    all_groups=(${lib.concatStringsSep " " groupNames})
    groups=("$@")
    (( ''${#groups[@]} )) || groups=("''${all_groups[@]}")
    for g in "''${groups[@]}"; do
      if [[ " ''${all_groups[*]} " != *" $g "* ]]; then
        log "ERROR: unknown backup group '$g' — known groups: ''${all_groups[*]}"
        exit 1
      fi
    done

    excludes=(
      ${excludeArgs}
    )

    ${groupFunctions}

    load_secrets
    log "starting backup to $REPO — groups: ''${groups[*]}"

    done_groups=()
    failed_groups=()
    for g in "''${groups[@]}"; do
      if app=$("inhibitor_$g"); then
        log "group $g skipped — $app is running"
        continue
      fi
      log "backing up group $g"
      rc=0
      "backup_group_$g" || rc=$?
      case $rc in
        0) done_groups+=("$g") ;;
        130)
          log "backup interrupted in group $g"
          exit 130
          ;;
        # restic exit code 3: snapshot created, but some files could not be read
        3)
          log "WARNING: group $g — some files could not be read"
          done_groups+=("$g")
          ;;
        *)
          log "ERROR: group $g failed (restic exit code $rc)"
          failed_groups+=("$g")
          ;;
      esac
    done

    # Retention per group: the tag (= group) defines the snapshot series, so a
    # changed path list in a group does not start a new series. Snapshots tagged
    # `baseline` (`restic tag --add baseline <id>`) are never forgotten.
    if (( ''${#done_groups[@]} )); then
      log "pruning old snapshots"
      "$RESTIC" --repo "$REPO" forget \
        --group-by host,tags \
        --keep-tag baseline \
        --keep-last ${toString cfg.keepLast} \
        --keep-monthly ${toString cfg.keepMonthly} \
        --prune \
        2>&1
    fi

    if (( ''${#failed_groups[@]} )); then
      log "backup finished with errors — failed groups: ''${failed_groups[*]}"
      exit 1
    fi
    log "backup complete — groups backed up: ''${done_groups[*]:-none}"
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
  imports = [
    (lib.mkRemovedOptionModule [
      "custom"
      "backup"
      "paths"
    ] "Use custom.backup.sets.<group>.paths.")
    (lib.mkRemovedOptionModule [
      "custom"
      "backup"
      "inhibitApps"
    ] "Use custom.backup.sets.<group>.inhibitApps.")
  ];

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

    sets = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            paths = lib.mkOption {
              type = lib.types.nonEmptyListOf lib.types.str;
              description = "Absolute paths backed up in this group (no globs).";
            };

            inhibitApps = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = ''
                Process names (matched via `pgrep -x`) that skip this group while
                they run. Use the exact process name as shown by Activity Monitor.
              '';
              example = [
                "rekordbox"
                "djay Pro AI"
              ];
            };
          };
        }
      );
      default = { };
      description = ''
        Backup groups. Each group is backed up in its own `restic backup` run,
        tagged with the group name (`backup-run [group…]`; restore with
        `--tag <group>`). Names must be valid shell identifiers.
      '';
      example = {
        music.paths = [ "/Users/jbl/Music/purchased" ];
        dj = {
          paths = [ "/Users/jbl/Library/Pioneer/rekordbox" ];
          inhibitApps = [ "rekordbox" ];
        };
      };
    };

    excludes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Patterns passed to restic --exclude (all groups).";
      example = [
        ".DS_Store"
        "node_modules"
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
      description = "Snapshots to keep per group (passed to restic forget --keep-last).";
    };

    keepMonthly = lib.mkOption {
      type = lib.types.int;
      default = 12;
      description = "Monthly snapshots to keep per group (passed to restic forget --keep-monthly).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (n: builtins.match "[A-Za-z_][A-Za-z0-9_]*" n != null) groupNames;
        message = "custom.backup.sets: group names must be valid shell identifiers.";
      }
      {
        assertion = groupNames != [ ];
        message = "custom.backup.sets: define at least one backup group.";
      }
    ];

    home.packages = [
      pkgs.restic
      backupScript
      checkScript
    ];

    launchd.agents = lib.mkIf cfg.automatic {
      # Daily backup agent — runs at cfg.schedule (default: 02:00), all groups.
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
