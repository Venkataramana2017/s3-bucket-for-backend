variable "aws_region" {
  description = "AWS region for the S3 bucket."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Local AWS profile; use null for environment or role credentials."
  type        = string
  default     = null
}

variable "aws_account_id" {
  description = "Expected AWS account to prevent deployment into another account."
  type        = string
  default     = "313932316713"
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "AWS account ID must contain 12 digits."
  }
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name."
  type        = string
  default     = "bucket-backend-terraform"
  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name)) &&
      !can(regex("^(xn--|sthree-|amzn-s3-demo-)|(-s3alias|--ol-s3|--x-s3|--table-s3)$", var.bucket_name))
    )
    error_message = "Use 3-63 lowercase letters, digits or hyphens, start and end with a letter or digit, and avoid S3 reserved prefixes/suffixes."
  }
}

variable "environment" {
  description = "Environment tag for the bucket."
  type        = string
  default     = "Dev"
}
