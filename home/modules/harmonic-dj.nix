{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.harmonicDj;

  /**
    APU Software Harmonic DJ — standalone app only (roadmap #32, evaluation phase).

    The vendor ships a notarized dmg that holds one distribution pkg with four
    components (Standalone, VST3, AU, AAX). Only the Standalone payload is
    unpacked: no plug-ins, no writes to `/Library`. The app bundle keeps its
    embedded AUv3 extension, since removing it would break the code signature.
    Fixup is off so the signed bundle stays byte-identical.

    Update: bump `version` and `hash`; old versions stay downloadable. See
    docs/harmonic-dj.md.
  */
  harmonicDj = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "apu-harmonic-dj";
    version = "1.2.9";

    src = pkgs.fetchurl {
      url = "https://apu.software/release/APU-HarmonicDJ-Installer-${version}.dmg";
      hash = "sha256-nFwzrmYOQsLMmlJrPJfaKlQ2XjgaEahySEDzbMyL7ao=";
    };

    nativeBuildInputs = with pkgs; [
      undmg
      xar
      cpio
      gzip
    ];

    sourceRoot = ".";
    unpackPhase = ''
      runHook preUnpack
      undmg "$src"
      xar -xf "APU-HarmonicDJ-${version}.pkg" \
        "APU_Harmonic_DJ_(Standalone_Application).pkg/Payload"
      mkdir payload
      gzip -dc "APU_Harmonic_DJ_(Standalone_Application).pkg/Payload" \
        | (cd payload && cpio -idm --quiet)
      runHook postUnpack
    '';

    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/Applications"
      cp -R "payload/Applications/APU Harmonic DJ.app" "$out/Applications/"
      runHook postInstall
    '';

    meta = {
      description = "Harmonic DJ by APU Software: key/mode, BPM and loudness analysis and set planning";
      homepage = "https://apu.software/hdj/";
      license = lib.licenses.unfree;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = lib.platforms.darwin;
    };
  };
in
{
  options.custom.harmonicDj = {
    enable = lib.mkEnableOption "APU Software Harmonic DJ (standalone app, evaluation phase)";
    package = lib.mkOption {
      type = lib.types.package;
      default = harmonicDj;
      description = "The Harmonic DJ app package (standalone app only, no DAW plug-ins).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Data, settings and backup are app-managed; see docs/SPEC.md (DJ Toolchain →
    # Harmonic DJ) and docs/harmonic-dj.md.
    home.packages = [ cfg.package ];
  };
}
