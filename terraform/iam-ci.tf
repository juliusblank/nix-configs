# IAM policies granting the GitHub Actions OIDC role the permissions needed to
# run `tofu plan` and `tofu apply` from CI.
#
# Three concerns are split into separate inline policies for clarity:
#   1. tofu-state-access  — S3 state bucket + DynamoDB lock table
#   2. iam-management     — OIDC provider + IAM role/policy CRUD (what this module owns)
#   3. nix-cache-mgmt     — bucket-level config for the nix cache S3 bucket
#
# The existing nix-cache-access policy (object-level read/write) is left in oidc.tf.

# Allows CI to read/write OpenTofu state in S3 and acquire the DynamoDB state lock.
resource "aws_iam_role_policy" "github_actions_tofu_state" {
  name = "tofu-state-access"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
        Resource = "arn:aws:dynamodb:${var.aws_region}:*:table/juliusblank-terraform-locks"
      }
    ]
  })
}

# Allows CI to manage the OIDC provider and IAM role that this terraform module owns.
# Scoped to exactly the actions tofu needs — no wildcard iam:*.
resource "aws_iam_role_policy" "github_actions_iam_management" {
  name = "iam-management"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
        ]
        Resource = "*"
      }
    ]
  })
}

# Allows CI to manage bucket-level configuration for the nix cache S3 bucket.
# Object-level access (GetObject/PutObject/ListBucket) is covered by the
# existing nix-cache-access policy in oidc.tf.
resource "aws_iam_role_policy" "github_actions_nix_cache_mgmt" {
  name = "nix-cache-management"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:GetLifecycleConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:GetBucketAcl",
          "s3:PutBucketAcl",
          "s3:GetBucketLogging",
          "s3:PutBucketLogging",
          "s3:GetEncryptionConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:GetBucketObjectLockConfiguration",
          "s3:GetBucketLocation",
          "s3:GetBucketCORS",
          "s3:PutBucketCORS",
          "s3:DeleteBucketCORS",
        ]
        Resource = "arn:aws:s3:::${var.nix_cache_bucket_name}"
      }
    ]
  })
}
