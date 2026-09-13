terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
}

variable "github_repository" {
  description = "GitHub owner/repository, with exact capitalization."
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use owner/repository."
  }
}

variable "aws_account_id" {
  type    = string
  default = "313932316713"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "managed_bucket_name" {
  type    = string
  default = "bucket-backend-terraform"
}

locals {
  suffix       = substr(sha256(var.github_repository), 0, 10)
  state_key    = "s3/terraform.tfstate"
  managed_arn  = "arn:aws:s3:::${var.managed_bucket_name}"
  environments = toset(["terraform-plan", "terraform-deploy"])
}

resource "aws_s3_bucket" "state" {
  bucket        = "tfstate-${var.aws_account_id}-${var.aws_region}-${local.suffix}"
  force_destroy = false
  lifecycle {
    prevent_destroy = true
  }
  tags = {
    ManagedBy = "Terraform"
    Purpose   = "GitHub Actions Terraform state"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

locals {
  github_iam_policies = { for environment in local.environments : environment => jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ManagedBucket"
        Effect   = "Allow"
        Action   = environment == "terraform-plan" ? ["s3:Get*", "s3:List*"] : ["s3:*"]
        Resource = [local.managed_arn, "${local.managed_arn}/*"]
      },
      {
        Sid      = "ListStateBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.state.arn
      },
      {
        Sid      = "StateFile"
        Effect   = "Allow"
        Action   = environment == "terraform-plan" ? ["s3:GetObject"] : ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.state.arn}/${local.state_key}"
      },
      {
        Sid      = "StateLock"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.state.arn}/${local.state_key}.tflock"
      }
    ]
  }) }
}

output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "state_key" {
  value = local.state_key
}

output "github_iam_policies" {
  description = "JSON policies to attach to existing IAM users for GitHub plan and deploy credentials. No users or access keys are created."
  value       = local.github_iam_policies
}
