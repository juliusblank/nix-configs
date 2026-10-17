# PR labels. Three groups:
#   - scope (`infra`, `ci`, `host:*`, …): applied by `.github/workflows/pr-labeler.yml`
#     from the file-path globs in `.github/labeler.yml`. Each one answers "what part
#     of the repo does this PR change" at a glance.
#   - type (`type:*`): applied by the same labeler from the branch prefix
#     (`feat/`, `fix/`, …), i.e. the conventional-commit type of the PR.
#   - status (`status:*`): set by hand. They are not in `.github/labeler.yml`, so
#     the labeler's `sync-labels` never removes them.
#
# Keep the set tight. A scope or type label only takes effect once it is also
# referenced from `.github/labeler.yml` with a matching rule.
locals {
  pr_labels = {
    infra = {
      color       = "1d76db"
      description = "Infrastructure as code (terraform/)"
    }
    ci = {
      color       = "d93f0b"
      description = "CI/CD workflows and GitHub config (.github/)"
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
      description = "Flake structure: flake.nix, lib/, overlays/"
    }
    deps = {
      color       = "fbca04"
      description = "Dependency bumps (flake.lock, Dependabot)"
    }
    docs = {
      color       = "0075ca"
      description = "Documentation only"
    }
    devshell = {
      color       = "006b75"
      description = "Dev shell and repo tooling (shell.nix, justfile, .envrc, …)"
    }

    "type:feat" = {
      color       = "a2eeef"
      description = "New feature (feat/ branch)"
    }
    "type:fix" = {
      color       = "e99695"
      description = "Bug fix (fix/ branch)"
    }
    "type:docs" = {
      color       = "c2e0c6"
      description = "Documentation change (docs/ branch)"
    }
    "type:chore" = {
      color       = "ededed"
      description = "Maintenance, releases (chore/ branch)"
    }
    "type:ci" = {
      color       = "f9d0c4"
      description = "CI change (ci/ branch)"
    }

    "status:evaluation" = {
      color       = "d4c5f9"
      description = "Evaluation in progress, do not merge yet (set by hand)"
    }
    "status:blocked" = {
      color       = "b60205"
      description = "Blocked by an external dependency (set by hand)"
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
