{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Public keys only — used for `git log --show-signature` / ssh signing verification.
  # All three keys are tagged as `dev@juliusblank.de` so commits verify as me regardless
  # of which host (and therefore which 1Password-served key) actually signed them.
  # The work key is NOT listed here — it signs only commits under the work includeIf
  # paths on concinnity, verified via `custom.extraAllowedSigners` as julius.blank@taktile.com.
  personalAllowedSigners = ''
    dev@juliusblank.de ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE6QO1pTcyRnhLUEBfx//MDIsM+APRr/Lniw/vXwzBWS
    dev@juliusblank.de ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE8Ng7SWMM85bS8nqmHqUZkEvgvrgNc/cnRLUIQyYDr3
    dev@juliusblank.de ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICqzDzUYBHkpAe0EURy0G91tZMiUcoZAO4qjmBy/fbRQ
  '';

in
{
  imports = [ ./modules/extra-allowed-signers.nix ];

  programs = {
    # --- Shell ---
    starship = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        add_newline = false;
        character = {
          success_symbol = "[❯](bold green)";
          error_symbol = "[❯](bold red)";
          vimcmd_symbol = "[](bold cyan)";
        };
      };
    };

    zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      plugins = [
        {
          name = "you-should-use";
          src = "${pkgs.zsh-you-should-use}/share/zsh/plugins/you-should-use";
        }
      ];
      completionInit = ''
        # Use cached compinit dump; full rescan only when dump is >24h old (~700ms → ~27ms).
        autoload -U compinit
        if [[ -f ~/.zcompdump(N.mh-24) ]]; then
          compinit -C
        else
          compinit
        fi
      '';
      initContent = ''
        source ${
          pkgs.runCommand "just-completions" { } ''
            ${pkgs.just}/bin/just --completions zsh > $out
          ''
        }

        # mkdir + cd in one step
        mcd() { mkdir -p "$1" && cd "$1" }

        # jj to leave insert mode (vi mode)
        bindkey jj vi-cmd-mode

        # zr [NAME] — attach or create a Zellij session with the "repo" layout.
        # NAME defaults to the current directory basename, so `zr` from a repo
        # root gives a session named after the repo.
        zr() {
          local name="''${1:-$(basename "$PWD")}"
          zellij attach "$name" 2>/dev/null \
            || zellij --session "$name" --layout repo
        }
      '';
      shellAliases = {
        ".." = "cd ..";
        "..." = "cd ../..";
        ll = "eza -la";
        ls = "eza";
        l = "eza -lhg --git --icons";
        la = "eza -lahg --git --icons";
        d1 = "eza --tree -L 1 -D";
        d2 = "eza --tree -L 2 -D";
        d3 = "eza --tree -L 3 -D";
        cat = "bat";
        wat = "bat --plain --wrap=never";
        df = "df -h";
        tree = "eza --tree";
        rz = "exec zsh";
        v = "$EDITOR";
        g = "git";
        gs = "git status";
        gd = "git diff";
        gc = "git commit";
        gp = "git push";
      };
    };

    # --- GitHub CLI (global; config + credential helper via home-manager) ---
    # Auth: run `gh auth login` once per machine — tokens live in Keychain / gh state,
    # not in this repo. `hosts` below are optional; omit to manage hosts.yml only via CLI.
    gh = {
      enable = true;
      settings.git_protocol = "ssh";
      # gh CLI extensions — home-manager symlinks each derivation's
      # bin/gh-<pname> into ~/.local/share/gh/extensions/<pname>/, so
      # `gh <name>` (e.g. `gh stack`) resolves without a manual install.
      extensions = [
        (import ../lib/gh-stack-bin.nix { inherit pkgs; } "0.1.0")
      ];
    };

    # --- Git (personal identity, always) ---
    git = {
      enable = true;
      signing = {
        # Signing key is set per-host (hosts/<name>/home.nix) — whichever key
        # the 1Password agent on that machine actually serves.
        signByDefault = true;
      };
      settings = {
        alias = {
          co = "checkout";
          cob = "checkout -b";
          st = "status -sb";
          dc = "diff --cached";
          ds = "diff --staged";
          ba = "branch -a";
          lg = "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
          bdm = "!git branch --merged | grep -v '*' | xargs -n 1 git branch -d";
        };
        user.name = "Julius Blank";
        user.email = "dev@juliusblank.de";
        init.defaultBranch = "main";
        push.autoSetupRemote = true;
        pull.rebase = true;
        gpg.format = "ssh";
        gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";
      };
    };

    # --- Neovim (shared; expand in-tree over time) ---
    neovim = {
      enable = true;
      # home-manager wraps this itself; must be *-unwrapped (has `.lua`) — not `pkgs.neovim`.
      package = pkgs.neovim-unwrapped;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      plugins = with pkgs.vimPlugins; [
        nvim-treesitter.withAllGrammars
        monokai-pro-nvim
      ];
      extraLuaConfig = ''
        -- TODO: migrate full Neovim layout (plugins, LSP, keymaps) from dotfiles / work machine.
        vim.opt.number = true
        vim.opt.relativenumber = true
        vim.cmd.colorscheme("monokai-pro")
        require('nvim-treesitter.configs').setup { highlight = { enable = true } }
      '';
    };

    # --- Direnv (auto-activate devShells) ---
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # --- Zellij (terminal multiplexer; one session per project/Claude run) ---
    #
    # `zr [NAME]` (zsh fn above) attaches or creates a session with the "repo"
    # layout from ./zellij/layouts/repo.kdl: claude pane on the left, shell on
    # the right. Zsh integration stays off deliberately — auto-attach misbehaves
    # inside Claude Code's PTY and nested shells.
    zellij = {
      enable = true;
      enableZshIntegration = false;
      settings = {
        default_shell = "zsh";
        theme = "ghostty-0x96f";
        pane_frames = false;
        simplified_ui = true;
        copy_command = "pbcopy";
        scroll_buffer_size = 50000;
      };
    };

    # Let home-manager manage itself
    home-manager.enable = true;
  };

  home = {
    file = {
      # Maps signing keys to emails for local `git log --show-signature` verification.
      # Hosts may append via `custom.extraAllowedSigners` (see concinnity).
      ".ssh/allowed_signers".text =
        personalAllowedSigners
        + lib.optionalString (config.custom.extraAllowedSigners != "") (
          "\n" + config.custom.extraAllowedSigners
        );

      # Zellij "repo" layout: claude left, shell right. `zr` zsh function
      # (above) attaches/creates a session with this layout.
      ".config/zellij/layouts/repo.kdl".text = ''
        layout {
            pane split_direction="vertical" {
                pane name="claude"
                pane name="shell"
            }
        }
      '';

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

    # --- Core CLI tools (every machine gets these) ---
    packages = with pkgs; [
      lazygit
      ripgrep
      fd
      jq
      yq-go
      bat
      eza
      fzf
      htop
      curl
      wget
      tree
      direnv
      nix-direnv
      gnupg
    ];

    # Import GitHub's GPG signing key so git can verify squash-merge commits
    # GitHub signs commits it creates (squash merges via web UI) with this key
    activation.importGitHubGpgKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${pkgs.curl}/bin/curl -sf https://github.com/web-flow.gpg \
        | ${pkgs.gnupg}/bin/gpg --import 2>&1 \
        || echo "Warning: GitHub GPG key import failed — will retry on next deploy"
    '';

    stateVersion = "25.05";
  };
}
