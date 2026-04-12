# --- GitHub Repository ---

resource "github_repository" "nix_configs" {
  name        = var.repo_name
  description = "Multi-system nix configuration"
  visibility  = "public"

  has_issues   = true
  has_projects = false
  has_wiki     = false

  allow_merge_commit = false
  allow_squash_merge = true
  allow_rebase_merge = false

  delete_branch_on_merge = true

  vulnerability_alerts = true
}

resource "github_branch_protection" "main" {
  repository_id = github_repository.nix_configs.node_id
  pattern       = "main"

  required_status_checks {
    strict = true
    contexts = [
      "check-flake",
    ]
  }

  required_pull_request_reviews {
    required_approving_review_count = 0  # PR required, no approvals needed (solo repo)
  }

  enforce_admins = true  # block direct pushes for everyone, including repo owner
}
