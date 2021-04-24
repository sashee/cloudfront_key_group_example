provider "aws" {
}

resource "aws_cloudfront_origin_access_identity" "OAI" {
}

resource "aws_s3_bucket" "protected" {
  force_destroy = "true"
}

resource "aws_s3_bucket_object" "secret_txt" {
  bucket = aws_s3_bucket.protected.bucket
  key    = "secret.txt"
  content = "This is a secret text!"
	content_type = "text/html"
}

resource "aws_s3_bucket_policy" "default" {
  bucket = aws_s3_bucket.protected.id
  policy = data.aws_iam_policy_document.default.json
}

data "aws_iam_policy_document" "default" {
  statement {
    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.protected.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.OAI.iam_arn]
    }
  }
}

resource "aws_cloudfront_distribution" "distribution" {
  origin {
    domain_name = aws_s3_bucket.protected.bucket_regional_domain_name
    origin_id   = "protected"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.OAI.cloudfront_access_identity_path
    }
  }

  enabled             = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "protected"

    default_ttl = 0
    min_ttl     = 0
    max_ttl     = 0

    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "https-only"
		compress = true
		trusted_key_groups = [aws_cloudfront_key_group.cf_keygroup.id]
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
	price_class = "PriceClass_100"
	is_ipv6_enabled = true
}

resource "random_id" "id" {
  byte_length = 8
}

resource "tls_private_key" "keypair" {
  algorithm   = "RSA"
}

resource "aws_ssm_parameter" "private_key" {
	name = "${random_id.id.hex}-private-key"
	type = "SecureString"
  value = tls_private_key.keypair.private_key_pem
}

resource "aws_cloudfront_public_key" "cf_key" {
  encoded_key = tls_private_key.keypair.public_key_pem
}

resource "aws_cloudfront_key_group" "cf_keygroup" {
  items   = [aws_cloudfront_public_key.cf_key.id]
  name    = "${random_id.id.hex}-group"
}

data "external" "build" {
	program = ["bash", "-c", <<EOT
(npm ci) >&2 && echo "{\"dest\": \".\"}"
EOT
]
	working_dir = "${path.module}/src"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/${random_id.id.hex}-lambda.zip"
	source_dir  = "${data.external.build.working_dir}/${data.external.build.result.dest}"
}

resource "aws_lambda_function" "lambda" {
  function_name = "api_example-${random_id.id.hex}-function"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  handler = "index.handler"
  runtime = "nodejs14.x"
  role    = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      CLOUDFRONT_DOMAIN = aws_cloudfront_distribution.distribution.domain_name
			KEYPAIR_ID = aws_cloudfront_public_key.cf_key.id
			PRIVATE_KEY_PARAMETER = aws_ssm_parameter.private_key.name
    }
  }
}

data "aws_iam_policy_document" "lambda_exec_role_policy" {
  statement {
    actions = [
			"ssm:GetParameter",
    ]
    resources = [
      aws_ssm_parameter.private_key.arn
    ]
  }
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }
}

resource "aws_cloudwatch_log_group" "loggroup" {
  name              = "/aws/lambda/${aws_lambda_function.lambda.function_name}"
  retention_in_days = 14
}

resource "aws_iam_role_policy" "lambda_exec_role" {
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_exec_role_policy.json
}

resource "aws_iam_role" "lambda_exec" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
	{
	  "Action": "sts:AssumeRole",
	  "Principal": {
		"Service": "lambda.amazonaws.com"
	  },
	  "Effect": "Allow"
	}
  ]
}
EOF
}

# API Gateway

resource "aws_apigatewayv2_api" "api" {
  name          = "api-${random_id.id.hex}"
  protocol_type = "HTTP"
  target        = aws_lambda_function.lambda.arn
}

resource "aws_lambda_permission" "apigw" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.arn
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

output "api_url" {
	value = aws_apigatewayv2_api.api.api_endpoint
}
