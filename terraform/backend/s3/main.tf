provider "aws" {
  region = "us-east-1" // Specify your desired region
}

resource "aws_s3_bucket" "backend" {
  bucket = "mtv-backend-bucket" // Replace with your unique bucket name

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name        = "Backend S3 Bucket"
    Environment = "Production"
  }
}

resource "aws_s3_bucket_public_access_block" "backend" {
  bucket = aws_s3_bucket.backend.id

  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
  restrict_public_buckets = true
}

output "backend_bucket_name" {
  value = aws_s3_bucket.backend.id
}
