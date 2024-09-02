provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "movie-storage-ik"
    key = "movies/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "terraform_lock_IaaC"
  }
}

resource "aws_dynamodb_table" "movies_table" {
  name = "terraform_lock_IaaC"
  billing_mode = "PAY_PER_REQUEST"
  hash_key = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Environment = "Production"
    Project = "TerraformStateLock"
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "movies_lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_policy"
  role = aws_iam_role.lambda_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
    {
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem"
      ],
      Effect = "Allow",
      Resource = aws_dynamodb_table.movies_table.arn
    },
    {
      Effect = "Allow",
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      Resource = "*"
    }
    ]
  })
}

resource "aws_lambda_function" "movies_lambda" {
  function_name = "dynamo-serverless-movieapi"
  role = aws_iam_role.lambda_exec_role.arn
  handler = "lambda_function.lambda_handler"
  runtime = "python3.11"
  filename = "lambda_newpackage.zip"
  source_code_hash = filebase64sha256("/opt/homebrew/bin/lambda_package/lambda_newpackage.zip")

  environment {
    variables = {
      OMDB_API_KEY = "4253964f"
    }
  }
}

resource "aws_api_gateway_rest_api" "movies_api" {
  name = "MoviesAPI"
  description = "API for fetching movie data and interacting with DynamoDB"
}

resource "aws_api_gateway_resource" "movies_resource" {
  rest_api_id = aws_api_gateway_rest_api.movies_api.id
  parent_id   = aws_api_gateway_rest_api.movies_api.root_resource_id
  path_part   = "movies"
}

resource "aws_api_gateway_method" "get_movies" {
  rest_api_id   = aws_api_gateway_rest_api.movies_api.id
  resource_id   = aws_api_gateway_resource.movies_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.movies_api.id
  resource_id = aws_api_gateway_resource.movies_resource.id
  http_method = aws_api_gateway_method.get_movies.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri = aws_lambda_function.movies_lambda.invoke_arn
}

resource "aws_api_gateway_deployment" "movies_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.movies_api.id
  stage_name  = "dev"
  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.movies_lambda.arn
}

output "api_gateway_url" {
  description = "Invoke URL for the deployed API Gateway"
  value       = "https://hlw4frj2bc.execute-api.us-east-1.amazonaws.com/dev"
}
