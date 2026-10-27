{
  config,
  pkgs,
  lib,
  ...
}:

let
  # $HOME for shell (zsh expands it); ~ for SSH config (ssh_config doesn't expand $HOME)
  onePasswordAgentSockShell = "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
  onePasswordAgentSockSsh = "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
in
{
  imports = [
    ./ghostty.nix
    ./modules/aerospace.nix
  ];

  # Link GUI apps from `home.packages` into ~/Applications/Home Manager Apps/ so Finder
  # and Spotlight can see them. (HM ≥25.11 defaults this off; Nix profile ~/.nix-profile/Applications
  # is often not indexed by Spotlight.)
  targets.darwin.linkApps.enable = true;

  # 1Password SSH agent key selection is host-specific — see each host's home.nix
  # for the agent.toml that controls which keys are exposed on that machine.
  programs = {
    # Point SSH_AUTH_SOCK at the 1Password agent so git SSH signing works.
    # Prune broken Homebrew completion dirs from fpath *before* home-manager runs compinit
    # (~570): stale `_brew` (symlink target missing) causes `compinit:527: no such file or directory`.
    zsh.initContent = lib.mkMerge [
      (lib.mkOrder 550 ''
        for _brew_site in /opt/homebrew/share/zsh/site-functions /usr/local/share/zsh/site-functions; do
          if [[ -d "$_brew_site" ]] && [[ ! -r "$_brew_site"/_brew ]]; then
            _new_fpath=()
            for _p in $fpath; do
              if [[ "$_p" != "$_brew_site" ]]; then
                _new_fpath+=("$_p")
              fi
            done
            fpath=($_new_fpath)
            unset _new_fpath _p
          fi
        done
        unset _brew_site
      '')
      ''
        export SSH_AUTH_SOCK="${onePasswordAgentSockShell}"
        source ${
          # op writes its config dir under $HOME; a private $TMPDIR avoids clashes
          # with other builds (a shared /tmp made this fail now and then).
          pkgs.runCommand "op-completions" { } ''
            export HOME=$TMPDIR
            ${pkgs._1password-cli}/bin/op completion zsh > $out
          ''
        }
      ''
    ];

    # Firefox data outside ~/Library/Application Support/Firefox. macOS 27 lets only
    # Mozilla-signed apps write there, so the nixpkgs build failed to lock its profile
    # ("A copy of Firefox is already open"; NixOS/nixpkgs#535123). With a non-default
    # configPath, home-manager passes `appDataDir` to the wrapper (MOZ_APP_DATA).
    # Only takes effect on hosts that enable programs.firefox. One-time data move:
    # docs/usage/nix-system.md.
    firefox.configPath = "Library/Application Support/org.nixos.firefox";

    # WORKAROUND (roadmap #35) — remove when NixOS/nixpkgs#571894 is fixed.
    # On macOS 27, LaunchServices loses the pid (-1) of an app whose bundle executable
    # is a shell wrapper that `exec`s the real binary. AeroSpace then never sees Firefox
    # and Cmd-Tab skips it. Make the real binary the bundle executable again and pass
    # the wrapper's MOZ_* variables through Info.plist `LSEnvironment` (applies to
    # Dock / Spotlight / `open` launches). The shell wrapper moves to bin/firefox for
    # direct exec (Granted's CustomBrowserPath).
    firefox.package = pkgs.firefox.overrideAttrs (old: {
      buildCommand = old.buildCommand + ''
        contents="$out/Applications/Firefox.app/Contents"
        mkdir -p "$out/bin"
        sed "s@$contents/MacOS/.firefox-old@$contents/MacOS/firefox@" \
          "$contents/MacOS/firefox" > "$out/bin/firefox"
        chmod +x "$out/bin/firefox"
        mv -f "$contents/MacOS/.firefox-old" "$contents/MacOS/firefox"

        env=""
        while IFS= read -r line; do
          name=''${line%%=*}
          value=''${line#*=}
          value=''${value#\'}
          value=''${value%\'}
          env+="<key>$name</key><string>$value</string>"
        done < <(sed -n "s/^export \(MOZ_[A-Z_]*='.*'\)$/\1/p" "$out/bin/firefox")

        plist="$contents/Info.plist"
        cp --remove-destination "$(readlink -f "$plist")" "$plist"
        chmod u+w "$plist"
        sed -i "s@^</dict>\$@<key>LSEnvironment</key><dict>$env</dict>\n</dict>@" "$plist"
      '';
    });

    # Git SSH signing via 1Password's op-ssh-sign. `user.signingKey` uses the
    # `key::` prefix (set in home/common.nix) so git looks the key up in the
    # agent; op-ssh-sign performs the actual signing operation with Touch ID.
    git.settings.gpg.ssh.program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";

    # SSH config — use 1Password SSH agent for all connections
    # OrbStack's include must come first (before any Host blocks)
    ssh = {
      enable = true;
      enableDefaultConfig = false;
      includes = [ "~/.orbstack/ssh/config" ];
      # Path contains a space ("Group Containers") — wrap in literal quotes so ssh_config parses it correctly
      settings."*".IdentityAgent = ''"${onePasswordAgentSockSsh}"'';
    };
  };

  home = {
    # macOS-specific packages
    packages = with pkgs; [
      coreutils # GNU coreutils on macOS
      gnused
      gnugrep
      _1password-cli
      awscli2
    ];

    # Home-manager owns ~/.config/git/config. Any legacy ~/.gitconfig (typically
    # written by 1Password's onboarding or work MDM) shadows it and injects the
    # wrong identity into every commit. Remove it on activation so home-manager
    # wins. Idempotent; only touches a regular file (never a symlink).
    activation.removeStrayGitconfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      gitconfig="$HOME/.gitconfig"
      if [ -f "$gitconfig" ] && [ ! -L "$gitconfig" ]; then
        $DRY_RUN_CMD rm -f "$gitconfig"
      fi
    '';

    # LaunchServices keeps every Firefox.app it has seen, including those of old Nix
    # generations (same bundle id org.nixos.firefox). A link click, the Dock or Spotlight
    # may then start an old build: with the macOS 27 wrapper bug (roadmap #35) AeroSpace
    # does not see it, and `login` opens a second instance with an empty window.
    # Unregister every other nix-store Firefox.app and register the current one. Only
    # the LaunchServices database changes; a rollback re-registers its own build.
    activation.registerCurrentFirefox = lib.mkIf (config.programs.firefox.finalPackage != null) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
        current="${config.programs.firefox.finalPackage}/Applications/Firefox.app"
        if [ -x "$lsregister" ] && [ -d "$current" ]; then
          "$lsregister" -dump 2>/dev/null \
            | ${pkgs.gnused}/bin/sed -n 's/^path: *\(\/nix\/store\/[^ ]*\/Applications\/Firefox\.app\) .*/\1/p' \
            | sort -u \
            | while IFS= read -r app; do
                [ "$app" = "$current" ] || $DRY_RUN_CMD "$lsregister" -u "$app"
              done
          $DRY_RUN_CMD "$lsregister" -f "$current"
        fi
      ''
    );
  };
}
