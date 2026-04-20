# IAM user for local tofu operations (just tf-plan, just tf-apply, just tf-import-*).
# Access keys are NOT managed here — they are created manually and stored in
# 1Password at op://Private/AWS Personal/access_key_id and secret_access_key.
#
# Import the existing user before applying:
#   just tf-import aws_iam_user.nix_configs_infra nix-configs-infra
#
# After applying, check for and remove any legacy inline policies that were
# attached manually before this resource was under tofu management.

# Local IAM user for running tofu locally via `just tf-plan` and `just tf-apply`.
resource "aws_iam_user" "nix_configs_infra" {
  name = "nix-configs-infra"

  tags = {
    project     = "nix-configs"
    repo        = "juliusblank/nix-configs"
    environment = "production"
  }

  lifecycle {
    prevent_destroy = true
    # Access keys are managed outside tofu — ignore any drift on the key count.
    ignore_changes = [tags_all]
  }
}

# Customer-managed policy granting the local user the same permissions as the CI
# OIDC role, so local and CI tofu runs have identical access. A managed policy is
# used instead of an inline policy because IAM inline user policies cap at 2048
# characters — too small for the full permission set needed here.
resource "aws_iam_policy" "nix_configs_infra" {
  name        = "nix-configs-infra-tofu-access"
  description = "Grants nix-configs-infra the permissions needed to run tofu locally."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # State file object access (read/write state, DynamoDB locking)
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::${var.state_bucket_name}/nix-configs/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.state_bucket_name}"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:*:table/${var.lock_table_name}"
      },
      # State bucket management (bucket-level config, required for state-backend.tf resources)
      {
        Effect   = "Allow"
        Action   = ["s3:Get*", "s3:Put*"]
        Resource = "arn:aws:s3:::${var.state_bucket_name}"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:ListTagsOfResource",
          "dynamodb:TagResource",
          "dynamodb:UntagResource",
          "dynamodb:DescribeTimeToLive",
          "dynamodb:DescribeContinuousBackups",
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:*:table/${var.lock_table_name}"
      },
      # Nix cache bucket — object-level and bucket-level config management
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.nix_cache_bucket_name}",
          "arn:aws:s3:::${var.nix_cache_bucket_name}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:Get*",
          "s3:Put*",
          "s3:Delete*",
        ]
        Resource = "arn:aws:s3:::${var.nix_cache_bucket_name}"
      },
      # IAM management — OIDC provider, CI role, and this user + policy
      {
        Effect = "Allow"
        Action = [
          "iam:GetOpenIDConnectProvider",
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider",
          "iam:GetRole",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:GetRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetUser",
          "iam:CreateUser",
          "iam:DeleteUser",
          "iam:UpdateUser",
          "iam:TagUser",
          "iam:UntagUser",
          "iam:ListUserTags",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:ListPolicyVersions",
          "iam:AttachUserPolicy",
          "iam:DetachUserPolicy",
          "iam:ListAttachedUserPolicies",
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach the managed policy to the user.
resource "aws_iam_user_policy_attachment" "nix_configs_infra" {
  user       = aws_iam_user.nix_configs_infra.name
  policy_arn = aws_iam_policy.nix_configs_infra.arn
}
