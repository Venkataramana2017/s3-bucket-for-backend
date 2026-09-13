resource "aws_s3_bucket" "demo_bucket" {
  bucket        = var.bucket_name
  force_destroy = false

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = var.bucket_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.demo_bucket.id

  lifecycle {
    create_before_destroy = true
  }

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse" {
  bucket = aws_s3_bucket.demo_bucket.id

  lifecycle {
    create_before_destroy = true
  }

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.demo_bucket.id

  lifecycle {
    create_before_destroy = true
  }

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "ownership" {
  bucket = aws_s3_bucket.demo_bucket.id

  lifecycle {
    create_before_destroy = true
  }

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
