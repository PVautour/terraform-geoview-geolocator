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
        Action   = ["s3:*", "s3-object-lambda:*"]
        Resource = "*"
      }
    ]
  })
}

# resource "aws_iam_policy" "cloudwatch_access_policy" {
#   name        = "cloudwatch-policy"
#   description = "cloudwatch IAM policy"

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "logs:CreateLogGroup",
#           "logs:CreateLogStream",
#           "logs:PutLogEvents",
#         ]
#         Resource = "*"
#       },
#     ]
#   })
# }

resource "aws_iam_role_policy_attachment" "s3_access_policy_attachment" {
  policy_arn = aws_iam_policy.s3_access_policy.arn
  role       = aws_iam_role.iam_for_lambda.name
}

# resource "aws_iam_role_policy_attachment" "cloudwatch_access_policy_attachment" {
#   policy_arn = aws_iam_policy.cloudwatch_access_policy.arn
#   role       = aws_iam_role.iam_for_lambda.name
# }

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

resource "aws_lambda_function" "example" {
  # If the file is not in the current working directory you will need to include a
  # path.module in the filename.
  filename         = "lambda_function_payload.zip"
  function_name    = "geoview-api-geolocator"
  role             = aws_iam_role.iam_for_lambda.arn
  handler          = "geolocator-lambda.lambda_handler"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 30
  runtime          = "python3.7"
}

resource "aws_api_gateway_rest_api" "example" {
  name        = "example-api"
  description = "Example API"
}

resource "aws_api_gateway_resource" "example" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  parent_id   = aws_api_gateway_rest_api.example.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "example" {
  rest_api_id   = aws_api_gateway_rest_api.example.id
  resource_id   = aws_api_gateway_resource.example.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_lambda_permission" "example" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.example.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.example.execution_arn}/*/*/*"
}

resource "aws_api_gateway_integration" "example" {
  rest_api_id             = aws_api_gateway_rest_api.example.id
  resource_id             = aws_api_gateway_resource.example.id
  http_method             = aws_api_gateway_method.example.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.example.invoke_arn
}
