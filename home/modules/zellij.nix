{ pkgs, ... }:

let
  /**
    Renders the shared Zellij "repo" layout with a parameterised Claude pane arg.
     `claudeArg` is the single flag passed to `claude` (`--continue` or `--resume`),
     which selects between auto-resume and the picker. All other panes (shell,
     git, status-bar) are identical across variants.
  */
  mkRepoLayout = claudeArg: ''
    layout {
        // The status-bar plugin has to appear in the layout's own pane tree —
        // `default_tab_template` only runs for explicit `tab {}` blocks, which
        // this layout doesn't use. Keep the status-bar inline as a 2-row
        // borderless pane under the content split.
        pane split_direction="horizontal" {
            pane split_direction="vertical" {
                pane name="claude" {
                    command "claude"
                    args "${claudeArg}"
                }
                pane split_direction="horizontal" {
                    pane name="shell"
                    pane name="git" {
                        // tig opens on the status view (closer to the lazygit
                        // workflow). tig only refreshes on user action, so it
                        // doesn't trigger periodic SSH-agent prompts the way
                        // lazygit's auto-fetch does.
                        command "tig"
                        args "status"
                    }
                }
            }
            pane size=2 borderless=true {
                plugin location="zellij:status-bar"
            }
        }
    }
  '';

in
{
  # Zellij terminal multiplexer — one session per project/Claude run.
  #
  # `zr [NAME]` / `zrp [NAME]` (zsh fns below) attach or create a session with
  # the "repo" / "repo-resume" layout. Both layouts share the same pane tree
  # (claude left, shell + tig right, status bar on top); they differ only in
  # whether the claude pane auto-resumes the latest conversation in cwd or
  # opens Claude's picker over past conversations.
  #
  # Zsh integration stays off deliberately — auto-attach misbehaves inside
  # Claude Code's PTY and nested shells.
  programs.zellij = {
    enable = true;
    enableZshIntegration = false;
    settings = {
      default_shell = "zsh";
      theme = "ghostty-0x96f";
      pane_frames = false;
      copy_command = "pbcopy";
      scroll_buffer_size = 50000;
    };
  };

  home = {
    packages = [ pkgs.tig ];

    file = {
      # "repo" layout — `--continue` auto-resumes the most recent conversation
      # in cwd (fresh otherwise). Use /clear inside Claude Code to drop the
      # loaded history and start a new conversation in the same pane.
      ".config/zellij/layouts/repo.kdl".text = mkRepoLayout "--continue";

      # "repo-resume" layout — `--resume` opens Claude's picker over past
      # conversations in cwd. Used by `zrp` when you want to pick explicitly.
      ".config/zellij/layouts/repo-resume.kdl".text = mkRepoLayout "--resume";

      # Zellij theme matched to the Ghostty "0x96f" theme (see home/ghostty.nix).
      # Shipped as a separate theme file so `programs.zellij.settings.theme`
      # above just needs to name it.
      ".config/zellij/themes/ghostty-0x96f.kdl".text = ''
        themes {
            ghostty-0x96f {
                fg "#FFFFFF"
                bg "#262427"
                black "#434343"
                red "#FF2740"
                green "#ABE047"
                yellow "#FFC24B"
                blue "#51A5FA"
                magenta "#FF75B5"
                cyan "#35BBB0"
                white "#FFFFFF"
                orange "#FFC24B"
            }
        }
      '';
    };
  };

  programs.zsh.initContent = ''
    # zr [NAME] — attach or create a Zellij session with the "repo" layout.
    # NAME defaults to the current directory basename, so `zr` from a repo
    # root gives a session named after the repo.
    #
    # Zellij 0.43 note: `-l/--layout` with `-s/--session` means "add this
    # layout as a new tab in an *existing* session". The flag that starts
    # a new session with a layout is `-n/--new-session-with-layout`, so
    # the create branch below uses that.
    zr() {
      local name="''${1:-$(basename "$PWD")}"
      if zellij list-sessions -s 2>/dev/null | grep -qx "$name"; then
        zellij attach "$name"
      else
        zellij -s "$name" -n repo
      fi
    }

    # zrp [NAME] — like zr, but the Claude pane runs `claude --resume`,
    # which opens the picker over conversations in the current directory.
    # Use when the cwd has multiple past conversations and you want to
    # pick one explicitly instead of auto-resuming the most recent.
    zrp() {
      local name="''${1:-$(basename "$PWD")}"
      if zellij list-sessions -s 2>/dev/null | grep -qx "$name"; then
        zellij attach "$name"
      else
        zellij -s "$name" -n repo-resume
      fi
    }
  '';
}
