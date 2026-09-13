output "bucket_name" {
  description = "Name of the S3 bucket."
  value       = aws_s3_bucket.demo_bucket.bucket
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.demo_bucket.arn
}

output "bucket_region" {
  description = "AWS region containing the bucket."
  value       = aws_s3_bucket.demo_bucket.region
}
