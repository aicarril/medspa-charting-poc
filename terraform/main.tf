terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "us-east-1"
}

variable "project" {
  default = "medspa"
}

data "aws_caller_identity" "current" {}

# S3 bucket for raw transcripts and audio
resource "aws_s3_bucket" "storage" {
  bucket = "${var.project}-storage-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "storage" {
  bucket                  = aws_s3_bucket.storage.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "storage" {
  bucket = aws_s3_bucket.storage.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# DynamoDB table for chart records
resource "aws_dynamodb_table" "charts" {
  name         = "${var.project}-charts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sessionId"

  attribute {
    name = "sessionId"
    type = "S"
  }
}

# DynamoDB table for chart templates
resource "aws_dynamodb_table" "templates" {
  name         = "${var.project}-templates"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "templateId"

  attribute {
    name = "templateId"
    type = "S"
  }
}

# IAM role for Lambda access to S3 and DynamoDB
resource "aws_iam_role" "lambda_role" {
  name = "${var.project}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.storage.arn,
          "${aws_s3_bucket.storage.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.charts.arn,
          aws_dynamodb_table.templates.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = [
          "arn:aws:bedrock:*:*:foundation-model/*",
          "arn:aws:bedrock:*:*:inference-profile/*"
        ]
      }
    ]
  })
}

# Cognito Identity Pool for browser access
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "${var.project}-identity-pool"
  allow_unauthenticated_identities = true
  allow_classic_flow               = true
}

resource "aws_iam_role" "cognito_unauth" {
  name = "${var.project}-cognito-unauth-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = "cognito-identity.amazonaws.com" }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
        }
        "ForAnyValue:StringLike" = {
          "cognito-identity.amazonaws.com:amr" = "unauthenticated"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "cognito_unauth_policy" {
  name = "${var.project}-cognito-unauth-policy"
  role = aws_iam_role.cognito_unauth.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["transcribe:StartStreamTranscription", "transcribe:StartStreamTranscriptionWebSocket"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject"]
        Resource = "${aws_s3_bucket.storage.arn}/*"
      },
      {
        Effect = "Allow"
        Action = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
        Resource = [
          aws_dynamodb_table.charts.arn,
          aws_dynamodb_table.templates.arn
        ]
      }
    ]
  })
}

resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id
  roles = {
    unauthenticated = aws_iam_role.cognito_unauth.arn
  }
}

output "identity_pool_id" {
  value = aws_cognito_identity_pool.main.id
}

# Lambda: Chart extraction
data "archive_file" "extract_chart" {
  type        = "zip"
  source_file = "${path.module}/../lambda/extract-chart/index.py"
  output_path = "${path.module}/../lambda/extract-chart/function.zip"
}

resource "aws_lambda_function" "extract_chart" {
  function_name    = "${var.project}-extract-chart"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.extract_chart.output_path
  source_code_hash = data.archive_file.extract_chart.output_base64sha256

  environment {
    variables = {
      CHARTS_TABLE    = aws_dynamodb_table.charts.name
      TEMPLATES_TABLE = aws_dynamodb_table.templates.name
      S3_BUCKET       = aws_s3_bucket.storage.id
      MODEL_ID        = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
    }
  }
}

# Lambda: API handler
data "archive_file" "api" {
  type        = "zip"
  source_file = "${path.module}/../lambda/api/index.py"
  output_path = "${path.module}/../lambda/api/function.zip"
}

resource "aws_lambda_function" "api" {
  function_name    = "${var.project}-api"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256

  environment {
    variables = {
      CHARTS_TABLE     = aws_dynamodb_table.charts.name
      TEMPLATES_TABLE  = aws_dynamodb_table.templates.name
      EXTRACT_FUNCTION = aws_lambda_function.extract_chart.function_name
    }
  }
}

# Add Lambda invoke permission for API Lambda to call extract Lambda
resource "aws_iam_role_policy" "lambda_invoke_policy" {
  name = "${var.project}-lambda-invoke-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.extract_chart.arn
    }]
  })
}

# API Gateway HTTP API
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "OPTIONS"]
    allow_headers = ["Content-Type"]
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# S3 bucket for frontend hosting
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project}-frontend-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload index.html
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  source       = "${path.module}/../frontend/index.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/../frontend/index.html")
}

# Error page
resource "aws_s3_object" "error" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "error.html"
  content      = "<html><body><h1>Error</h1><p><a href='/'>Go home</a></p></body></html>"
  content_type = "text/html"
}

# CloudFront OAC
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project}-frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 300
    max_ttl     = 1200
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Bucket policy for CloudFront OAC
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
        }
      }
    }]
  })
}

output "frontend_url" {
  value = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "api_url" {
  value = aws_apigatewayv2_stage.default.invoke_url
}

output "extract_chart_function_name" {
  value = aws_lambda_function.extract_chart.function_name
}

output "extract_chart_function_arn" {
  value = aws_lambda_function.extract_chart.arn
}

output "s3_bucket_name" {
  value = aws_s3_bucket.storage.id
}

output "charts_table_name" {
  value = aws_dynamodb_table.charts.name
}

output "templates_table_name" {
  value = aws_dynamodb_table.templates.name
}

output "lambda_role_arn" {
  value = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  value = aws_iam_role.lambda_role.name
}
