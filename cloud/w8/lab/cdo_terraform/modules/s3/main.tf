resource "aws_s3_bucket" "static_assets" {
  bucket = "tf-final-project-assets-${var.environment}-2025"   # phải unique toàn cầu

  tags = {
    Name        = "${var.environment}-static-assets"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}