terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "ca-central-1"
}

resource "aws_iam_policy" "s3_access_policy" {
  name = "s3_access_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.geolocator.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_access_policy_attachment" {
  policy_arn = aws_iam_policy.s3_access_policy.arn
  role       = aws_iam_role.iam_for_lambda.name
}

resource "aws_s3_bucket" "geolocator" {
  bucket = "geolocator-cf"
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = "iam_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "api-lambda"
  output_path = "lambda_function_payload.zip"
}

resource "aws_lambda_function" "test_lambda" {
  # If the file is not in the current working directory you will need to include a
  # path.module in the filename.
  filename      = "lambda_function_payload.zip"
  function_name = "geoview-api-geolocator"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "geolocator-lambda.lambda_handler"

  source_code_hash = data.archive_file.lambda.output_base64sha256

  runtime = "python3.9"
}

# Define the API Gateway
resource "aws_api_gateway_rest_api" "example" {
  name        = "example-api-gateway"
  description = "Example API Gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Define the API Gateway resource
resource "aws_api_gateway_resource" "example" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  parent_id   = aws_api_gateway_rest_api.example.root_resource_id
  path_part   = "v0"
}

# Define the API Gateway method
resource "aws_api_gateway_method" "example" {
  rest_api_id   = aws_api_gateway_rest_api.example.id
  resource_id   = aws_api_gateway_resource.example.id
  http_method   = "GET"
  authorization = "None"
  request_parameters = {
    "method.request.querystring.q"    = true
    "method.request.querystring.lang" = false
    "method.request.querystring.keys" = false
  }
}

# Define the API Gateway integration with Lambda
resource "aws_api_gateway_integration" "example" {
  rest_api_id             = aws_api_gateway_rest_api.example.id
  resource_id             = aws_api_gateway_resource.example.id
  http_method             = aws_api_gateway_method.example.http_method
  integration_http_method = "GET"
  type                    = "AWS"
  uri                     = aws_lambda_function.test_lambda.invoke_arn
}

# # Define the API Gateway deployment
# resource "aws_apigatewayv2_deployment" "example" {
#   api_id = aws_api_gateway_rest_api.example.id
# }

# # Define the API Gateway stage
# resource "aws_apigatewayv2_stage" "example" {
#   name   = "dev"
#   api_id = aws_api_gateway_rest_api.example.id
# }
