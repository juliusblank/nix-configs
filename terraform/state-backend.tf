# S3 bucket and DynamoDB table that back the OpenTofu state backend.
#
# Bootstrap sequence (chicken-egg):
#   1. `just setup-terraform-backend` — creates these resources imperatively via the AWS CLI.
#   2. `just tf-import-backend`       — imports them into tofu state so tofu owns them going
#                                       forward. Run once after the first bootstrap.
#   After that, tofu manages these resources like any other.
#
# IMPORTANT: never run `tofu destroy` while these resources are live state backends.
# `prevent_destroy = true` is set on all resources here as a safeguard.

# S3 bucket that stores the OpenTofu state file.
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name

  tags = {
    project     = "nix-configs"
    repo        = "juliusblank/nix-configs"
    environment = "production"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Versioning keeps a full history of state files — essential for recovery after bad applies.
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access — state files must never be publicly readable.
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# DynamoDB table used for state locking — prevents concurrent applies from corrupting state.
# LockID is the partition key required by the OpenTofu S3 backend.
resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    project     = "nix-configs"
    repo        = "juliusblank/nix-configs"
    environment = "production"
  }

  lifecycle {
    prevent_destroy = true
  }
}
