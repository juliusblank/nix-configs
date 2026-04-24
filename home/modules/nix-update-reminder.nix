{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.nixUpdateReminder;
  stateFile = "${config.home.homeDirectory}/.local/state/nix-update-check";

  # Compares locked revs in flake.lock against upstream branch HEADs via
  # git ls-remote. No tarball downloads, no nix evaluation, no daemon involvement.
  # Safe to run at any time, including during audio/DJ workloads.
  checkScript = pkgs.writeShellApplication {
    name = "nix-update-check";
    runtimeInputs = with pkgs; [
      jq
      git
    ];
    text = ''
      lock_file="${cfg.repoPath}/flake.lock"
      state_file="${stateFile}"

      mkdir -p "$(dirname "$state_file")"
      : > "$state_file"

      [[ -f "$lock_file" ]] || exit 0

      # Bail immediately if offline — don't hang or log spurious errors
      if ! timeout 5 git ls-remote https://github.com 2>/dev/null | head -1 &>/dev/null; then
        exit 0
      fi

      # Extract github-type inputs that track a branch (have a ref field)
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
    '';
  };
in
{
  /**
    Periodically checks for nix flake input updates and reminds on shell start.
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
  };

  config = lib.mkIf cfg.enable {
    # Daily background check — runs 24h after its own last run, never on load.
    # Niced to the floor so it cannot impact foreground work (audio, etc.).
    launchd.agents.nix-update-check = {
      enable = true;
      config = {
        ProgramArguments = [ "${checkScript}/bin/nix-update-check" ];
        StartInterval = 86400;
        RunAtLoad = false;
        Nice = 19;
        LowPriorityIO = true;
        ProcessType = "Background";
        StandardOutPath = "/tmp/nix-update-check.log";
        StandardErrorPath = "/tmp/nix-update-check.log";
      };
    };

    programs.zsh.initExtra = ''
      _nix_update_reminder() {
        local lock_file="${cfg.repoPath}/flake.lock"
        local state_file="${stateFile}"

        [[ ! -f "$lock_file" ]] && return
        [[ ! -f "$state_file" ]] && return
        [[ ! -s "$state_file" ]] && return

        # Suppress if flake.lock is newer than state file — user already updated
        [[ "$lock_file" -nt "$state_file" ]] && return

        local now mtime age_days
        now=$(date +%s)
        mtime=$(stat -f %m "$lock_file" 2>/dev/null) || return
        age_days=$(( (now - mtime) / 86400 ))

        [[ $age_days -lt ${toString cfg.staleDays} ]] && return

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
