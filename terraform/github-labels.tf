# Scope labels applied to PRs by `.github/workflows/pr-labeler.yml` based on
# the file-path globs in `.github/labeler.yml`.
#
# Keep the set tight: each label must answer "what part of the repo does this
# PR change" at a glance. Adding a new label here only takes effect once it
# is also referenced from `.github/labeler.yml` with a matching path glob.
locals {
  pr_labels = {
    infra = {
      color       = "1d76db"
      description = "Infrastructure as code (terraform/, infra workflow)"
    }
    ci = {
      color       = "d93f0b"
      description = "CI/CD workflows and automation"
    }
    "host:serenity" = {
      color       = "c5def5"
      description = "Changes to the serenity host (personal MacBook)"
    }
    "host:concinnity" = {
      color       = "bfd4f2"
      description = "Changes to the concinnity host (work MacBook)"
    }
    home = {
      color       = "0e8a16"
      description = "Shared home-manager modules (home/)"
    }
    flake = {
      color       = "5319e7"
      description = "Flake inputs or structural flake.nix changes"
    }
    deps = {
      color       = "fbca04"
      description = "Dependency bumps (flake.lock)"
    }
    docs = {
      color       = "0075ca"
      description = "Documentation only"
    }
  }
}

# PR scope labels. Declared via for_each so adding a label is a one-line change.
resource "github_issue_label" "pr_scope" {
  for_each = local.pr_labels

  repository  = github_repository.nix_configs.name
  name        = each.key
  color       = each.value.color
  description = each.value.description
}
