# S3 bucket used as a nix binary cache — stores signed store paths shared across all hosts and CI.
resource "aws_s3_bucket" "nix_cache" {
  bucket = var.nix_cache_bucket_name

  tags = {
    project     = "nix-configs"
    repo        = "juliusblank/nix-configs"
    environment = "production"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Versioning kept enabled so nix cache objects can be recovered if accidentally overwritten.
resource "aws_s3_bucket_versioning" "nix_cache" {
  bucket = aws_s3_bucket.nix_cache.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle rules to bound storage cost — old versions expire after 30 days, entries after 90.
resource "aws_s3_bucket_lifecycle_configuration" "nix_cache" {
  bucket = aws_s3_bucket.nix_cache.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "expire-narinfo"
    status = "Enabled"

    filter {
      prefix = ""
    }

    # Cache entries older than 90 days — adjust as needed
    expiration {
      days = 90
    }
  }
}

# ACL-based public access is blocked; a bucket policy grants public read below.
# restrict_public_buckets and block_public_policy must be false to allow the policy.
resource "aws_s3_bucket_public_access_block" "nix_cache" {
  bucket = aws_s3_bucket.nix_cache.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

# Allow unauthenticated reads so nix can use this bucket as a substituter without
# AWS credentials. Store paths are content-addressed and signature-verified by nix,
# so public read does not weaken integrity.
resource "aws_s3_bucket_policy" "nix_cache_public_read" {
  bucket = aws_s3_bucket.nix_cache.id

  # public_access_block must be applied first to avoid a conflict on creation
  depends_on = [aws_s3_bucket_public_access_block.nix_cache]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicRead"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = "${aws_s3_bucket.nix_cache.arn}/*"
      }
    ]
  })
}
