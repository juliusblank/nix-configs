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

variable "nix_cache_bucket_name" {
  description = "S3 bucket for nix binary cache"
  type        = string
  default     = "juliusblank-nix-cache"
}
