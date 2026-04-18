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

## Naming

- All resource, variable, output, data source, and local names use `snake_case`
- Names are purpose-bound — describe what the thing *is*, not what type it is
  - Good: `nix_cache`, `nix_configs`, `github_actions_role`
  - Bad: `bucket`, `repo`, `role`

## Variables

- Every `variable` block must have a `description`
- Use `nullable = true` when `null` is a meaningful value the caller can explicitly pass
  (a caller-supplied `null` overrides any default; use `nullable = false` to fall back to
  the default instead)
- Add a `validation` block only when:
  - Passing an invalid value would be dangerous or destructive, or
  - The set of valid values is known and constrained

```hcl
# AWS region for all resources. Must be an eu- region per data residency policy.
variable "aws_region" {
  type        = string
  default     = "eu-central-1"
  nullable    = false
  description = "AWS region for all resources."

  validation {
    condition     = startswith(var.aws_region, "eu-")
    error_message = "Only eu- regions are permitted."
  }
}
```

## Outputs

- Every `output` block must have a `description`
- Set `sensitive = true` explicitly on any output whose value is a secret — do not rely
  on Terraform inferring sensitivity from the source

## Version pinning

- **Providers**: pin to an exact version — prefer deterministic builds over ranges

  ```hcl
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.43.0"
    }
  }
  ```

- **Modules**: also pin to exact versions
- **Own modules**: may be used freely
- **External modules**: require thorough review before use; document the review result
  in a comment block at the call site:

  ```hcl
  # External module — reviewed 2025-04-18.
  # Verdict: safe. Only creates IAM role + trust policy; no data exfiltration risk.
  # Source: https://github.com/example/terraform-aws-oidc — pinned to v2.1.0.
  module "oidc" {
    source  = "example/oidc/aws"
    version = "= 2.1.0"
    ...
  }
  ```

## Locals

- Use `locals` to deduplicate values used more than once *and* to give complex
  expressions a readable name even if used only once
- Local names use `snake_case`

## AWS resource tagging

Every AWS resource must carry these tags with exactly these values:

```hcl
tags = {
  project     = "nix-configs"
  repo        = "juliusblank/nix-configs"
  environment = "production"
}
```

Tag keys are always lowercase.

## Resource iteration

- Use `for_each` when creating multiple instances of a resource (state is keyed by
  map key, not index — safer to add/remove entries)
- Use `count` only for simple boolean toggles: `count = var.enable_x ? 1 : 0`

## Data sources

- Prefer data sources over hardcoding IDs or ARNs
- Name data sources the same way as resources: `snake_case`, purpose-bound
- Any data source that references a resource from another project or remote state
  must be documented in `terraform/dependencies.md`

## Lifecycle rules

- `prevent_destroy = true` is **required** on all stateful production resources
  (S3 buckets, DynamoDB tables, IAM roles, etc.)
- `prevent_destroy = true` is **recommended** on stateful non-production resources
- `ignore_changes` is only permitted when a field is managed outside of OpenTofu
  (e.g. by an auto-scaling policy or an external process); always add a comment
  explaining what manages the field and why it is excluded:

  ```hcl
  lifecycle {
    ignore_changes = [
      # Managed by the auto-scaling policy — OpenTofu must not reset it on apply.
      desired_count,
    ]
  }
  ```

## File organisation

- One `.tf` file per concern (e.g. `oidc.tf`, `s3-cache.tf`, `github.tf`)
- Variable declarations in `variables.tf`, outputs in `outputs.tf`
- Provider and backend config in `providers.tf`
- Never commit `.tfplan` files or override files (`*.override.tf`)
- Secrets injected via `op read` in the justfile — never hardcoded in `.tf` files
