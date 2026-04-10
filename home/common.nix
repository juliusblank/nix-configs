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
    extraConfig = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = true;
    };
  };

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

  home.stateVersion = "24.05";
}
