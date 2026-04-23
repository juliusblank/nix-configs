/**
  AWS CLI configuration module.

  Writes a writable `~/.aws/config` on every home-manager activation.
  The file is written (not symlinked) so that Granted and the AWS SDK
  can update it at runtime without hitting read-only nix store errors.

  Credential processes are declared per-profile; the file itself never
  contains secrets.
*/
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.aws;

  renderProfile =
    p:
    lib.concatStringsSep "\n" (
      [
        "[profile ${p.name}]"
        "region = ${p.region}"
      ]
      ++ lib.optional (p.credentialProcess != null) "credential_process = ${p.credentialProcess}"
    )
    + "\n";

  configFile = pkgs.writeText "aws-config" (
    ''
      [default]
      region = eu-central-1

    ''
    + lib.concatMapStrings renderProfile cfg.profiles
  );
in
{
  options.custom.aws = {
    enable = lib.mkEnableOption "AWS CLI configuration";

    profiles = lib.mkOption {
      default = [ ];
      description = "List of AWS CLI profiles to declare in ~/.aws/config.";
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Profile name. Convention: <org>_<account>_<user>.";
            };
            region = lib.mkOption {
              type = lib.types.str;
              default = "eu-central-1";
            };
            credentialProcess = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                credential_process command string. Null for placeholder profiles.
                Use a nix-store script path (pkgs.writeShellScript) for stable
                absolute paths that survive PATH changes.
              '';
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    home.activation.awsConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/.aws"
      install -m 600 ${configFile} "$HOME/.aws/config"
    '';
  };
}
