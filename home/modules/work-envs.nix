{
  config,
  lib,
  ...
}:

let
  cfg = config.custom.workEnvs;
  home = config.home.homeDirectory;

  # One store file per project — stable content means direnv allow survives rebuilds.
  envrcFile =
    project: builtins.toFile "envrc-${project}" "use flake ${cfg.envsRepoPath}#${project}\n";
in
{
  /**
    Places a .envrc in each listed project directory pointing at the central
    devshell-configs flake. Only writes if the project directory already exists
    (i.e. the repo is cloned). Uses install rather than a symlink so that
    direnv allow survives nix rebuilds as long as the content is unchanged.
  */
  options.custom.workEnvs = {
    enable = lib.mkEnableOption "work project dev environments via direnv";

    envsRepoPath = lib.mkOption {
      type = lib.types.str;
      description = "Absolute path to the devshell-configs repo on this machine.";
    };

    baseDir = lib.mkOption {
      type = lib.types.str;
      description = "Path relative to home under which work repos are cloned (e.g. github/taktile-org).";
    };

    projects = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Repo names to manage. Each gets a .envrc pointing at the matching devShell in envsRepoPath.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.activation.workEnvs = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      lib.concatMapStrings (project: ''
        if [[ -d "${home}/${cfg.baseDir}/${project}" ]]; then
          install -m 644 ${envrcFile project} "${home}/${cfg.baseDir}/${project}/.envrc"
        fi
      '') cfg.projects
    );
  };
}
