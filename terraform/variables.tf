variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "github_owner" {
  description = "GitHub username"
  type        = string
  default     = "juliusblank"
}

variable "repo_name" {
  description = "GitHub repository name"
  type        = string
  default     = "nix-configs"
}

variable "state_bucket_name" {
  description = "S3 bucket for Terraform state (created by just setup-terraform-backend)"
  type        = string
  default     = "juliusblank-terraform-state"
}

# Name of the DynamoDB table used for OpenTofu state locking.
# Created by `just setup-terraform-backend` on first bootstrap; managed by tofu thereafter.
variable "lock_table_name" {
  description = "DynamoDB table for OpenTofu state locking"
  type        = string
  default     = "juliusblank-terraform-locks"
}

variable "nix_cache_bucket_name" {
  description = "S3 bucket for nix binary cache"
  type        = string
  default     = "juliusblank-nix-cache"
}

# 1Password Service Account token for the github-actions-nix-configs SA.
# Stored in op://infrastructure/github-actions-nix-configs/token.
# Injected by the justfile via TF_VAR_op_service_account_token.
# GitHub PAT for the GitHub provider. Passed as TF_VAR_github_token to avoid
# collision with the GITHUB_TOKEN Actions injects automatically in CI.
variable "github_token" {
  description = "GitHub Personal Access Token for the GitHub provider."
  type        = string
  sensitive   = true
}

variable "op_service_account_token" {
  description = "1Password Service Account token used by GitHub Actions CI to fetch secrets from the github_nix-configs vault."
  type        = string
  sensitive   = true
}
