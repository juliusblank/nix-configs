{ lib, ... }:
{
  options.custom.extraAllowedSigners = lib.mkOption {
    type = lib.types.lines;
    default = "";
    description = ''
      Extra lines appended to ~/.ssh/allowed_signers (e.g. work identity on concinnity).
      Public keys only; same format as ssh-keygen allowed_signers.
    '';
  };
}
