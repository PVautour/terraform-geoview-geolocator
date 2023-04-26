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

resource "aws_iam_role_policy_attachment" "s3_access_policy_attachment" {
  policy_arn = aws_iam_policy.s3_access_policy.arn
  role       = aws_iam_role.iam_for_lambda.name
}

resource "aws_iam_role_policy_attachment" "lambda_basic_policy_attachement" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.iam_for_lambda.name
}

resource "aws_s3_bucket" "geolocator" {
  bucket = "geolocator-tf"
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

resource "aws_lambda_function" "api-lambda" {
  # If the file is not in the current working directory you will need to include a
  # path.module in the filename.
  filename         = "lambda_function_payload.zip"
  function_name    = "geolocator-lambda-tf"
  role             = aws_iam_role.iam_for_lambda.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 30
  memory_size      = 3009
  runtime          = "python3.7"
}

resource "aws_api_gateway_rest_api" "rest-api" {
  name        = "geolocator-api-tf"
  description = "An api that can query multiple external services for geospatial data"
}

resource "aws_api_gateway_resource" "rest-api-resource" {
  rest_api_id = aws_api_gateway_rest_api.rest-api.id
  parent_id   = aws_api_gateway_rest_api.rest-api.root_resource_id
  path_part   = "v0"
}

resource "aws_api_gateway_method" "get" {
  rest_api_id   = aws_api_gateway_rest_api.rest-api.id
  resource_id   = aws_api_gateway_resource.rest-api-resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_lambda_permission" "allow-exec-from-api" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api-lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.rest-api.execution_arn}/*/*/*"
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.rest-api.id
  resource_id             = aws_api_gateway_resource.rest-api-resource.id
  http_method             = aws_api_gateway_method.get.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.api-lambda.invoke_arn
  request_templates = {
    "application/json" = <<EOF
        ##  See http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-mapping-template-reference.html
        ##  This template will pass through all parameters including path, querystring, header, stage variables, and context through to the integration endpoint via the body/payload
        #set($allParams = $input.params())
        {
        "params" : {
        #foreach($type in $allParams.keySet())
            #set($params = $allParams.get($type))
        "$type" : {
            #foreach($paramName in $params.keySet())
            "$paramName" : "$util.escapeJavaScript($params.get($paramName))"
                #if($foreach.hasNext),#end
            #end
        }
            #if($foreach.hasNext),#end
        #end
        }
        }    
  EOF
  }
}

resource "aws_api_gateway_integration_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.rest-api.id
  resource_id = aws_api_gateway_resource.rest-api-resource.id
  http_method = aws_api_gateway_method.get.http_method
  status_code = "200"

  response_templates = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.rest-api.id
  resource_id = aws_api_gateway_resource.rest-api-resource.id
  http_method = aws_api_gateway_method.get.http_method
  status_code = "200"
}
resource "aws_api_gateway_integration_response" "MyDemoIntegrationResponse" {
  rest_api_id = aws_api_gateway_rest_api.rest-api.id
  resource_id = aws_api_gateway_resource.rest-api-resource.id
  http_method = aws_api_gateway_method.get.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code
}
