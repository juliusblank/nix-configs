{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.nixUpdateReminder;
  stateFile = "${config.home.homeDirectory}/.local/state/nix-update-check";
  timestampFile = "${config.home.homeDirectory}/.local/state/nix-update-check.timestamp";

  # Compares locked revs in flake.lock against upstream branch HEADs via
  # git ls-remote. No tarball downloads, no nix evaluation, no daemon involvement.
  checkScript = pkgs.writeShellApplication {
    name = "nix-update-check";
    runtimeInputs = with pkgs; [
      jq
      git
      coreutils
    ];
    text = ''
      lock_file="${cfg.repoPath}/flake.lock"
      state_file="${stateFile}"
      timestamp_file="${timestampFile}"

      mkdir -p "$(dirname "$state_file")"

      # Bail immediately if offline
      if ! timeout 5 git ls-remote https://github.com &>/dev/null; then
        exit 0
      fi

      : > "$state_file"

      jq -r '
        .nodes | to_entries[] |
        select(.key != "root") |
        select(.value.original.type == "github") |
        select(.value.original.ref != null) |
        [.key, .value.original.owner, .value.original.repo, .value.original.ref, .value.locked.rev] |
        @tsv
      ' "$lock_file" | while IFS=$'\t' read -r name owner repo_name ref locked_rev; do
        remote_rev=$(
          timeout 15 git ls-remote "https://github.com/$owner/$repo_name.git" \
            "refs/heads/$ref" 2>/dev/null | cut -f1
        )
        [[ -z "$remote_rev" ]] && continue
        [[ "$remote_rev" == "$locked_rev" ]] && continue
        echo "$name" >> "$state_file"
      done

      date +%s > "$timestamp_file"
    '';
  };
in
{
  /**
    Checks for nix flake input updates on terminal open and reminds if stale.
  */
  options.custom.nixUpdateReminder = {
    enable = lib.mkEnableOption "nix flake update reminder";

    repoPath = lib.mkOption {
      type = lib.types.str;
      description = "Absolute path to the nix-configs repository.";
    };

    staleDays = lib.mkOption {
      type = lib.types.int;
      default = 7;
      description = "Days since last flake.lock update before showing the reminder.";
    };

    recheckHours = lib.mkOption {
      type = lib.types.int;
      default = 12;
      description = "Minimum hours between upstream checks to avoid re-running on every terminal open.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.zsh.initExtra = ''
      _nix_update_reminder() {
        local lock_file="${cfg.repoPath}/flake.lock"
        local state_file="${stateFile}"
        local timestamp_file="${timestampFile}"

        [[ ! -f "$lock_file" ]] && return

        local mtime age_days
        mtime=$(stat -f %m "$lock_file" 2>/dev/null) || return
        age_days=$(( ($(date +%s) - mtime) / 86400 ))

        # flake.lock is recent enough — no reminder needed
        [[ $age_days -lt ${toString cfg.staleDays} ]] && return

        # Decide whether to re-run the upstream check
        local now last_checked hours_since_check
        now=$(date +%s)
        last_checked=0
        [[ -f "$timestamp_file" ]] && last_checked=$(cat "$timestamp_file" 2>/dev/null || echo 0)
        hours_since_check=$(( (now - last_checked) / 3600 ))

        if [[ $hours_since_check -ge ${toString cfg.recheckHours} ]]; then
          ${checkScript}/bin/nix-update-check &
          return
        fi

        # flake.lock updated since last check — user already ran just update
        [[ "$lock_file" -nt "$timestamp_file" ]] && return

        [[ ! -s "$state_file" ]] && return

        echo ""
        echo "  nix-configs: $age_days days since last update — pending:"
        while IFS= read -r input; do
          [[ -n "$input" ]] && echo "    • $input"
        done < "$state_file"
        echo "  → cd ${cfg.repoPath} && just update"
        echo ""
      }
      _nix_update_reminder
    '';
  };
}
