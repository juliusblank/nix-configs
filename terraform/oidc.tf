# --- OIDC Federation: GitHub Actions → AWS ---

# The OIDC provider (one per AWS account, may already exist)
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["ffffffffffffffffffffffffffffffffffffffff"] # GitHub's OIDC uses a well-known CA

  # If this resource already exists in your account, import it:
  # terraform import aws_iam_openid_connect_provider.github arn:aws:iam::oidc-provider/token.actions.githubusercontent.com
}

# IAM role that GitHub Actions assumes
resource "aws_iam_role" "github_actions" {
  name = "nix-config-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Scoped to this repo only
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_owner}/${var.repo_name}:*"
          }
        }
      }
    ]
  })
}

# Policy: read/write to nix cache bucket only
resource "aws_iam_role_policy" "github_actions_nix_cache" {
  name = "nix-cache-access"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.nix_cache.arn,
          "${aws_s3_bucket.nix_cache.arn}/*",
        ]
      }
    ]
  })
}

# Store the role ARN as a GitHub Actions secret
resource "github_actions_secret" "aws_role_arn" {
  repository      = github_repository.nix_config.name
  secret_name     = "AWS_ROLE_ARN"
  plaintext_value = aws_iam_role.github_actions.arn
}

# Store the nix cache bucket name as a variable
resource "github_actions_variable" "nix_cache_bucket" {
  repository    = github_repository.nix_config.name
  variable_name = "NIX_CACHE_BUCKET"
  value         = aws_s3_bucket.nix_cache.id
}
