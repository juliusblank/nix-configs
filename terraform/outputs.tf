output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions"
  value       = aws_iam_role.github_actions.arn
}

output "nix_cache_bucket" {
  description = "S3 bucket name for nix binary cache"
  value       = aws_s3_bucket.nix_cache.id
}

output "repository_url" {
  description = "GitHub repository URL"
  value       = github_repository.nix_configs.html_url
}
