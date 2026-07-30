# Fetches a specific github/gh-stack release binary from GitHub.
#
# github/gh-stack ships pre-built platform binaries as unarchived release
# assets (not a tarball). home-manager's programs.gh.extensions places the
# derivation's `bin/gh-<pname>` at `~/.local/share/gh/extensions/<pname>/`
# so `gh stack` is discovered by the gh CLI.
#
# Usage (in home/common.nix):
#   programs.gh.extensions = [
#     (import ../lib/gh-stack-bin.nix { inherit pkgs; } "0.1.0")
#   ];
#
# Adding hashes for a new version:
#   nix store prefetch-file --hash-type sha256 --json \
#     https://github.com/github/gh-stack/releases/download/v<VERSION>/<PLATFORM>
#   where PLATFORM is: darwin-arm64, linux-amd64, darwin-amd64, linux-arm64

{ pkgs }:

version:

let
  system = pkgs.stdenv.hostPlatform.system;

  platformMap = {
    "aarch64-darwin" = "darwin-arm64";
    "x86_64-linux" = "linux-amd64";
    "x86_64-darwin" = "darwin-amd64";
    "aarch64-linux" = "linux-arm64";
  };

  # SRI hashes for fetchurl (raw binary), keyed by version and nix system.
  hashes = {
    "0.1.0" = {
      "aarch64-darwin" = "sha256-XKmCQaJl1t4BgJXNrl88QNpcp4JFDuwOqRqo4+sYMQM=";
      "x86_64-linux" = "sha256-NYVS3X3OCkbOFT/hlicM7EgrhPCAlHiQqtQGGo1EvAs=";
    };
  };

  platform = platformMap.${system} or (throw "gh-stack-bin: unsupported system ${system}");

  hash =
    (hashes.${version} or (throw ''
      gh-stack-bin: no hashes for version ${version}.
      Add hashes to lib/gh-stack-bin.nix. See file header for instructions.
    '')
    ).${system} or (throw ''
      gh-stack-bin: no hash for gh-stack ${version} on ${system}.
      Add the hash to lib/gh-stack-bin.nix under hashes."${version}"."${system}".
      See file header for instructions.
    '');
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "gh-stack";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://github.com/github/gh-stack/releases/download/v${version}/${platform}";
    inherit hash;
  };

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    install -m755 $src $out/bin/gh-stack
  '';

  meta = {
    description = "GitHub CLI extension for stacked pull requests (pinned binary)";
    homepage = "https://github.com/github/gh-stack";
  };
}
