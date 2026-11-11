# GitHub repository configuration — manages settings, merge strategy, and rulesets.
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

  lifecycle {
    prevent_destroy = true
  }
}

# Ruleset for main — PRs required for everyone, CI must pass, no deletion or force push.
# Created in the GitHub UI, imported below; replaces the former classic branch
# protection (github_branch_protection.main). No bypass actors, so it binds admins too.
resource "github_repository_ruleset" "main" {
  name        = "main"
  repository  = github_repository.nix_configs.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["refs/heads/main"]
      exclude = []
    }
  }

  rules {
    deletion         = true
    non_fast_forward = true

    required_status_checks {
      strict_required_status_checks_policy = true
      do_not_enforce_on_create             = true

      required_check {
        context        = "CI passed"
        integration_id = 15368 # GitHub Actions
      }
    }

    pull_request {
      required_approving_review_count   = 0          # PR required, no approvals needed (solo repo)
      allowed_merge_methods             = ["squash"] # matches allow_squash_merge only
      dismiss_stale_reviews_on_push     = false
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_review_thread_resolution = false
    }
  }
}

# Ruleset that requests a Copilot code review on PRs to the default branch, drafts included,
# and again on every push.
# Created by the repo's Copilot settings page, imported below. Follows
# .github/copilot-instructions.md.
resource "github_repository_ruleset" "copilot_review" {
  name        = "Copilot review for default branch"
  repository  = github_repository.nix_configs.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion         = true
    non_fast_forward = true

    copilot_code_review {
      review_on_push             = true # costs premium requests per push
      review_draft_pull_requests = true
    }
  }
}

# One-time adoption of the two rulesets created in the GitHub UI. No-ops after the first
# apply; remove them in a later change.
import {
  to = github_repository_ruleset.main
  id = "${var.repo_name}:27024812"
}

import {
  to = github_repository_ruleset.copilot_review
  id = "${var.repo_name}:27024789"
}
