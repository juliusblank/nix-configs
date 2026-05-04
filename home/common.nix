{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Public keys only — used for `git log --show-signature` / ssh signing verification.
  personalAllowedSigners = ''
    dev@juliusblank.de ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE6QO1pTcyRnhLUEBfx//MDIsM+APRr/Lniw/vXwzBWS
    dev@juliusblank.de ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE8Ng7SWMM85bS8nqmHqUZkEvgvrgNc/cnRLUIQyYDr3
  '';
in
{
  imports = [ ./modules/extra-allowed-signers.nix ];

  # --- Shell ---
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      add_newline = false;
      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
      };
    };
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
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
    '';
    shellAliases = {
      ".." = "cd ..";
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
  programs.gh = {
    enable = true;
    settings.git_protocol = "ssh";
  };

  # --- Git (personal identity, always) ---
  programs.git = {
    enable = true;
    signing = {
      # Personal SSH key served by 1Password agent — private key never leaves 1Password
      key = "key::ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE6QO1pTcyRnhLUEBfx//MDIsM+APRr/Lniw/vXwzBWS";
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

  # Maps signing keys to emails for local `git log --show-signature` verification.
  # Hosts may append via `custom.extraAllowedSigners` (see concinnity).
  home.file.".ssh/allowed_signers".text =
    personalAllowedSigners
    + lib.optionalString (config.custom.extraAllowedSigners != "") (
      "\n" + config.custom.extraAllowedSigners
    );

  # --- Core CLI tools (every machine gets these) ---
  home.packages = with pkgs; [
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

  # --- Neovim (shared; expand in-tree over time) ---
  programs.neovim = {
    enable = true;
    # home-manager wraps this itself; must be *-unwrapped (has `.lua`) — not `pkgs.neovim`.
    package = pkgs.neovim-unwrapped;
    defaultEditor = false;
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
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Import GitHub's GPG signing key so git can verify squash-merge commits
  # GitHub signs commits it creates (squash merges via web UI) with this key
  home.activation.importGitHubGpgKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.curl}/bin/curl -sf https://github.com/web-flow.gpg \
      | ${pkgs.gnupg}/bin/gpg --import 2>&1 \
      || echo "Warning: GitHub GPG key import failed — will retry on next deploy"
  '';

  # Let home-manager manage itself
  programs.home-manager.enable = true;

  home.stateVersion = "25.05";
}
