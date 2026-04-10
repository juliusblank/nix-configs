# --- S3 Nix Binary Cache ---

resource "aws_s3_bucket" "nix_cache" {
  bucket = var.nix_cache_bucket_name
}

resource "aws_s3_bucket_versioning" "nix_cache" {
  bucket = aws_s3_bucket.nix_cache.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "nix_cache" {
  bucket = aws_s3_bucket.nix_cache.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

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

resource "aws_s3_bucket_public_access_block" "nix_cache" {
  bucket = aws_s3_bucket.nix_cache.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
