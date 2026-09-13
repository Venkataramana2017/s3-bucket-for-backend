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

variable "existing_oidc_provider_arn" {
  description = "Existing token.actions.githubusercontent.com provider ARN, if one already exists in this account."
  type        = string
  default     = null
}

locals {
  suffix       = substr(sha256(var.github_repository), 0, 10)
  state_key    = "s3/terraform.tfstate"
  managed_arn  = "arn:aws:s3:::${var.managed_bucket_name}"
  oidc_arn     = var.existing_oidc_provider_arn != null ? var.existing_oidc_provider_arn : aws_iam_openid_connect_provider.github[0].arn
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

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.existing_oidc_provider_arn == null ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github" {
  for_each = local.environments
  name     = "s3-${each.key}-${local.suffix}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:${each.key}"
      } }
    }]
  })
}

resource "aws_iam_role_policy" "github" {
  for_each = local.environments
  role     = aws_iam_role.github[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ManagedBucket"
        Effect   = "Allow"
        Action   = each.key == "terraform-plan" ? ["s3:Get*", "s3:List*"] : ["s3:*"]
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
        Action   = each.key == "terraform-plan" ? ["s3:GetObject"] : ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.state.arn}/${local.state_key}"
      },
      {
        Sid      = "StateLock"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.state.arn}/${local.state_key}.tflock"
      }
    ]
  })
}

output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "state_key" {
  value = local.state_key
}

output "github_environment_roles" {
  value = { for name, role in aws_iam_role.github : name => role.arn }
}
