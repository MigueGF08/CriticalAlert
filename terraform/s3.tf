resource "aws_s3_bucket" "web_bucket" {
  bucket = "${var.project_name}-web-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.web_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.web_bucket.id
  index_document { suffix = "index.html" }
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.web_bucket.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "PublicReadGetObject",
      Effect    = "Allow",
      Principal = "*",
      Action    = "s3:GetObject",
      Resource  = "${aws_s3_bucket.web_bucket.arn}/*"
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.public_access]
}

resource "aws_s3_object" "html" {
  bucket       = aws_s3_bucket.web_bucket.id
  key          = "index.html"
  source       = "../web/index.html"
  content_type = "text/html"
}

resource "aws_s3_object" "config" {
  bucket       = aws_s3_bucket.web_bucket.id
  key          = "config.json"
  content      = jsonencode({ api_url = "${aws_apigatewayv2_api.http_api.api_endpoint}/result" })
  content_type = "application/json"
  source       = "../web/config.json"
}
