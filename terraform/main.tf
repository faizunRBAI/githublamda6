terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Project name used as a prefix for resource names"
  type        = string
}

variable "tf_state_bucket" {
  description = "S3 bucket that holds Terraform state and Lambda zip artifacts"
  type        = string
}

# IAM role for the Lambda function
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function — zip lives in the shared TF_STATE_BUCKET
resource "aws_lambda_function" "app" {
  function_name = "${var.project_name}-function"
  role          = aws_iam_role.lambda_exec.arn

  # Artifact uploaded by CI
  s3_bucket = var.tf_state_bucket
  s3_key    = "${var.project_name}/lambda.zip"

  handler     = "lambda_handler.handler"
  runtime     = "python3.11"
  timeout     = 30
  memory_size = 256

  environment {
    variables = {
      APP_ENV = "production"
    }
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

# Lambda Function URL — public, no IAM auth
resource "aws_lambda_function_url" "app_url" {
  function_name      = aws_lambda_function.app.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["*"]
    expose_headers    = []
    max_age           = 86400
  }
}

resource "aws_lambda_permission" "allow_public_url" {
  statement_id           = "AllowPublicFunctionURL"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.app.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

output "function_url" {
  description = "Public HTTPS endpoint for the Lambda function"
  value       = aws_lambda_function_url.app_url.function_url
}

output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.app.function_name
}