# =============================================================================
# Lambda Functions for AgentCore Gateway
# =============================================================================

# -----------------------------------------------------------------------------
# Response Interceptor Lambda
# -----------------------------------------------------------------------------

data "archive_file" "interceptor" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/interceptor"
  output_path = "${path.module}/.terraform/tmp/interceptor.zip"
}

resource "aws_lambda_function" "interceptor" {
  function_name = "${var.project_name}-interceptor"
  role          = aws_iam_role.lambda_interceptor.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.interceptor.output_path
  source_code_hash = data.archive_file.interceptor.output_base64sha256

  timeout     = 30
  memory_size = 256

  environment {
    variables = {
      TOOL_PERMISSIONS = jsonencode(var.tool_permissions)
      LOG_LEVEL        = "INFO"
    }
  }

  tags = {
    Name = "${var.project_name}-interceptor"
  }
}

resource "aws_cloudwatch_log_group" "interceptor" {
  name              = "/aws/lambda/${aws_lambda_function.interceptor.function_name}"
  retention_in_days = 14
}

# -----------------------------------------------------------------------------
# MCP Tools Target Lambda
# -----------------------------------------------------------------------------

data "archive_file" "mcp_tools" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/mcp_tools"
  output_path = "${path.module}/.terraform/tmp/mcp_tools.zip"
}

resource "aws_lambda_function" "mcp_tools" {
  function_name = "${var.project_name}-mcp-tools"
  role          = aws_iam_role.lambda_mcp_tools.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.mcp_tools.output_path
  source_code_hash = data.archive_file.mcp_tools.output_base64sha256

  timeout     = 60
  memory_size = 256

  environment {
    variables = {
      LOG_LEVEL = "INFO"
    }
  }

  tags = {
    Name = "${var.project_name}-mcp-tools"
  }
}

resource "aws_cloudwatch_log_group" "mcp_tools" {
  name              = "/aws/lambda/${aws_lambda_function.mcp_tools.function_name}"
  retention_in_days = 14
}

# -----------------------------------------------------------------------------
# IAM Roles for Lambda Functions
# -----------------------------------------------------------------------------

# Interceptor Lambda Role
resource "aws_iam_role" "lambda_interceptor" {
  name = "${var.project_name}-interceptor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "interceptor_basic" {
  role       = aws_iam_role.lambda_interceptor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# MCP Tools Lambda Role
resource "aws_iam_role" "lambda_mcp_tools" {
  name = "${var.project_name}-mcp-tools-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "mcp_tools_basic" {
  role       = aws_iam_role.lambda_mcp_tools.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# -----------------------------------------------------------------------------
# Lambda Permissions for AgentCore Gateway
# -----------------------------------------------------------------------------

resource "aws_lambda_permission" "interceptor_gateway" {
  statement_id  = "AllowAgentCoreGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.interceptor.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagentcore_gateway.main.gateway_arn
}

resource "aws_lambda_permission" "mcp_tools_gateway" {
  statement_id  = "AllowAgentCoreGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mcp_tools.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagentcore_gateway.main.gateway_arn
}
