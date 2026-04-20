{ pkgs, ... }:

{
  # --- Shell ---
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

  # --- Git (personal identity, always) ---
  programs.git = {
    enable = true;
    userName = "Julius Blank";
    userEmail = "dev@juliusblank.de";
    signing = {
      # Personal SSH key served by 1Password agent — private key never leaves 1Password
      key = "key::ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE6QO1pTcyRnhLUEBfx//MDIsM+APRr/Lniw/vXwzBWS";
      signByDefault = true;
    };
    extraConfig = {
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
  ];

  # --- Direnv (auto-activate devShells) ---
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Let home-manager manage itself
  programs.home-manager.enable = true;

  home.stateVersion = "25.05";
}
