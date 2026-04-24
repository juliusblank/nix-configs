{ pkgs, lib, ... }:

{
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
    shellAliases = {
      ll = "eza -la";
      ls = "eza";
      cat = "bat";
      tree = "eza --tree";
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
      user.name = "Julius Blank";
      user.email = "dev@juliusblank.de";
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = true;
      gpg.format = "ssh";
      gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";
    };
  };

  # Maps the signing key to the personal email for local signature verification.
  # Not a secret — this is the public key.
  home.file.".ssh/allowed_signers".text = ''
    dev@juliusblank.de ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE6QO1pTcyRnhLUEBfx//MDIsM+APRr/Lniw/vXwzBWS
    dev@juliusblank.de ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE8Ng7SWMM85bS8nqmHqUZkEvgvrgNc/cnRLUIQyYDr3
  '';

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
    extraLuaConfig = ''
      -- TODO: migrate full Neovim layout (plugins, LSP, keymaps) from dotfiles / work machine.
      vim.opt.number = true
      vim.opt.relativenumber = true
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
    if ! ${pkgs.gnupg}/bin/gpg --list-keys B5690EEEBB952194 > /dev/null 2>&1; then
      $DRY_RUN_CMD ${pkgs.curl}/bin/curl -sf https://github.com/web-flow.gpg | ${pkgs.gnupg}/bin/gpg --import
    fi
  '';

  # Let home-manager manage itself
  programs.home-manager.enable = true;

  home.stateVersion = "25.05";
}
