# OIDC provider for GitHub Actions — one per AWS account, allows token-based role assumption.
# If this resource already exists in your account, import it:
#   tofu import aws_iam_openid_connect_provider.github \
#     arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["ffffffffffffffffffffffffffffffffffffffff"] # GitHub's OIDC uses a well-known CA

  tags = {
    project     = "nix-configs"
    repo        = "juliusblank/nix-configs"
    environment = "production"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# IAM role assumed by GitHub Actions via OIDC — scoped to this repository only.
resource "aws_iam_role" "github_actions" {
  name = "nix-configs-github-actions"

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

  tags = {
    project     = "nix-configs"
    repo        = "juliusblank/nix-configs"
    environment = "production"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Inline policy granting the CI role read/write access to the nix cache bucket only.
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

# Exposes the CI role ARN to GitHub Actions as a repository secret.
resource "github_actions_secret" "aws_role_arn" {
  repository      = github_repository.nix_configs.name
  secret_name     = "AWS_ROLE_ARN"
  plaintext_value = aws_iam_role.github_actions.arn
}

# Exposes the 1Password Service Account token to GitHub Actions.
# The SA has read-only access to the github/nix-configs vault and is used by
# 1password/load-secrets-action to fetch live secrets on every CI run.
# Value comes from op://Private/1Password SA github-actions-nix-configs/token
# and is injected by the justfile via TF_VAR_op_service_account_token.
resource "github_actions_secret" "op_service_account_token" {
  repository      = github_repository.nix_configs.name
  secret_name     = "OP_SERVICE_ACCOUNT_TOKEN"
  plaintext_value = var.op_service_account_token
}

# Exposes the nix cache bucket name to GitHub Actions as a repository variable.
resource "github_actions_variable" "nix_cache_bucket" {
  repository    = github_repository.nix_configs.name
  variable_name = "NIX_CACHE_BUCKET"
  value         = aws_s3_bucket.nix_cache.id
}
