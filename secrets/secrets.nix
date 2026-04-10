# Agenix secrets configuration
# Each secret is encrypted to specific host SSH keys
#
# Usage:
#   1. Add host public keys below
#   2. Create secrets: agenix -e secrets/my-secret.age
#   3. Reference in nix config: age.secrets.my-secret.file = ./my-secret.age;
#
# See: https://github.com/ryantm/agenix

let
  # Host SSH public keys (add after first deploy)
  # macbook-private = "ssh-ed25519 AAAA...";
  # macbook-work = "ssh-ed25519 AAAA...";
  # pi-moodpi = "ssh-ed25519 AAAA...";

  # All hosts that should be able to decrypt all secrets
  allHosts = [
    # macbook-private
    # macbook-work
    # pi-moodpi
  ];
in
{
  # Example:
  # "secrets/wifi-password.age".publicKeys = allHosts;
}
