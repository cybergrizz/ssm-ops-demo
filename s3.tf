resource "aws_s3_bucket" "ssm-demo-bucket2026" {
  bucket = "ssm-demo-bucket"

  tags = {
    Name        = "My ssm-demo-bucket"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_public_access_block" "ssm_demo_bucket_pab" {
  bucket = aws_s3_bucket.ssm-demo-bucket2026.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "ssm_demo_bucket_versioning" {
  bucket = aws_s3_bucket.ssm-demo-bucket2026.id

  versioning_configuration {
    status = "Enabled"
  }
}