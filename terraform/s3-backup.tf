# S3 bucket used as a restic backup repository — stores encrypted backup data for serenity
# (and future hosts). Each host writes under its own prefix (e.g. serenity/).
# The bucket is private; restic encrypts all data before uploading.
resource "aws_s3_bucket" "backup" {
  bucket = var.backup_bucket_name

  tags = {
    project     = "nix-configs"
    repo        = "juliusblank/nix-configs"
    environment = "production"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Versioning kept enabled so backup objects can be recovered if accidentally overwritten.
resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Expire old object versions after 90 days — restic manages current object retention
# via `restic forget --prune` in the backup script.
resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# Block all public access — backup data must never be publicly readable.
resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
