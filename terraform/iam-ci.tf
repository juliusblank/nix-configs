# IAM policies granting the GitHub Actions OIDC role the permissions needed to
# run `tofu plan` and `tofu apply` from CI.
#
# Three concerns are split into separate inline policies for clarity:
#   1. tofu-state-access  — S3 state bucket + DynamoDB lock table
#   2. iam-management     — OIDC provider + IAM role/policy CRUD (what this module owns)
#   3. nix-cache-mgmt     — bucket-level config for the nix cache S3 bucket
#
# The existing nix-cache-access policy (object-level read/write) is left in oidc.tf.

# Allows CI to read/write OpenTofu state objects in S3 and acquire the DynamoDB state lock.
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
        Resource = "arn:aws:dynamodb:${var.aws_region}:*:table/${var.lock_table_name}"
      }
    ]
  })
}

# Allows CI to manage the state S3 bucket and DynamoDB lock table as tofu resources.
# Needed now that state-backend.tf declares these as managed resources — tofu reads
# bucket policy, versioning, public-access-block, and table tags/TTL on every refresh.
# Uses Get*/Put* wildcards on the bucket (not objects) to avoid whack-a-mole with
# individual bucket-level actions, matching the pattern used for nix-cache-management.
resource "aws_iam_role_policy" "github_actions_state_backend_mgmt" {
  name = "state-backend-management"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
          # User + managed policy management (nix-configs-infra user and its tofu-access policy)
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

# Allows CI to manage bucket-level configuration for the nix cache S3 bucket.
# Uses GetBucket*/PutBucket* wildcards to cover all attributes the AWS provider
# reads/writes on refresh — avoids whack-a-mole with individual actions.
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
        # s3:Get*/Put*/Delete* covers all bucket-level config actions the AWS provider
        # reads and writes on refresh — including non-GetBucket* actions like
        # GetAccelerateConfiguration, GetEncryptionConfiguration, GetLifecycleConfiguration.
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:Get*",
          "s3:Put*",
          "s3:Delete*",
        ]
        Resource = "arn:aws:s3:::${var.nix_cache_bucket_name}"
      }
    ]
  })
}
