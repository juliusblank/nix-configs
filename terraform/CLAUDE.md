# terraform/ — OpenTofu (HCL) conventions

This directory contains all OpenTofu infrastructure definitions: GitHub repo settings,
branch protection, AWS OIDC federation, and the S3 nix binary cache bucket.

## Formatting

- Indentation: 2 spaces (enforced by `tofu fmt` — always run it before committing)
- Max line length: 100 characters
- Run `tofu validate` after any structural change

```bash
cd terraform && tofu fmt && tofu validate
```

## Doc comments

Every `resource`, `variable`, `output`, and `module` block must have a `#` description comment
immediately above it. Describe what it is and any non-obvious constraints or dependencies.

```hcl
# GitHub repository configuration for nix-configs.
# Manages branch protection, squash-merge enforcement, and topic tags.
resource "github_repository" "nix_configs" {
  ...
}

# ARN of the OIDC role assumed by GitHub Actions for CI jobs.
# Scoped to this repository only — no cross-repo access.
output "github_actions_role_arn" {
  ...
}
```

## Conventions

- One `.tf` file per concern (e.g. `oidc.tf`, `s3-cache.tf`, `github.tf`)
- Variable declarations live in `variables.tf`, outputs in `outputs.tf`
- Provider and backend config live in `providers.tf`
- Never commit a `.tfplan` file or override file
- Secrets are injected via `op read` in the justfile — never hardcoded
