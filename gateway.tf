# =============================================================================
# AgentCore Gateway with Response Interceptor
# =============================================================================

# -----------------------------------------------------------------------------
# Gateway Service Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "gateway" {
  name = "${var.project_name}-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock-agentcore.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Gateway が Lambda を呼び出すための権限
resource "aws_iam_role_policy" "gateway_lambda" {
  name = "lambda-invoke"
  role = aws_iam_role.gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.interceptor.arn,
          aws_lambda_function.mcp_tools.arn
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# AgentCore Gateway
# -----------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway" "main" {
  name     = "${var.project_name}-gateway"
  role_arn = aws_iam_role.gateway.arn

  # MCP プロトコルを使用
  protocol_type = "MCP"

  # JWT 認証 (Cognito)
  authorizer_type = "CUSTOM_JWT"

  authorizer_configuration {
    custom_jwt_authorizer {
      # Cognito の OIDC discovery URL
      discovery_url = "https://cognito-idp.${data.aws_region.current.id}.amazonaws.com/${aws_cognito_user_pool.main.id}/.well-known/openid-configuration"

      # 許可するオーディエンス (JWT の aud クレームを検証)
      allowed_audience = [aws_cognito_user_pool_client.gateway.id]
    }
  }

  # Response Interceptor 設定
  interceptor_configuration {
    # RESPONSE インターセプターとして設定
    interception_points = ["RESPONSE"]

    # Lambda インターセプター
    interceptor {
      lambda {
        arn = aws_lambda_function.interceptor.arn
      }
    }

    # リクエストヘッダーを渡す（Authorization ヘッダーから JWT を取得するため）
    input_configuration {
      pass_request_headers = true
    }
  }

  # ログレベル
  exception_level = "DEBUG"

  description = "AgentCore Gateway with permission-based tool filtering"

  tags = {
    Name = "${var.project_name}-gateway"
  }
}

# -----------------------------------------------------------------------------
# Gateway Targets - 各ツールに対して1つのターゲット
# -----------------------------------------------------------------------------

locals {
  tools = {
    list_documents = {
      description = "List available documents in the system"
      input_schema = {
        type        = "object"
        description = "No parameters required"
      }
    }
    search_documents = {
      description = "Search documents by query"
      input_schema = {
        type        = "object"
        description = "Search parameters"
        properties = {
          query = {
            name        = "query"
            type        = "string"
            description = "Search query string"
            required    = true
          }
        }
      }
    }
    read_document = {
      description = "Read a specific document"
      input_schema = {
        type        = "object"
        description = "Document identifier"
        properties = {
          document_id = {
            name        = "document_id"
            type        = "string"
            description = "Document ID to read"
            required    = true
          }
        }
      }
    }
    write_document = {
      description = "Create or update a document"
      input_schema = {
        type        = "object"
        description = "Document data"
        properties = {
          title = {
            name        = "title"
            type        = "string"
            description = "Document title"
            required    = true
          }
          content = {
            name        = "content"
            type        = "string"
            description = "Document content"
            required    = true
          }
        }
      }
    }
    delete_document = {
      description = "Delete a document (admin only)"
      input_schema = {
        type        = "object"
        description = "Document identifier"
        properties = {
          document_id = {
            name        = "document_id"
            type        = "string"
            description = "Document ID to delete"
            required    = true
          }
        }
      }
    }
    list_users = {
      description = "List all users"
      input_schema = {
        type        = "object"
        description = "No parameters required"
      }
    }
    read_user = {
      description = "Get user details"
      input_schema = {
        type        = "object"
        description = "User identifier"
        properties = {
          user_id = {
            name        = "user_id"
            type        = "string"
            description = "User ID to retrieve"
            required    = true
          }
        }
      }
    }
    admin_reset = {
      description = "Reset system (admin only)"
      input_schema = {
        type        = "object"
        description = "Reset parameters"
        properties = {
          target = {
            name        = "target"
            type        = "string"
            description = "Target to reset (cache, database, etc)"
            required    = true
          }
        }
      }
    }
  }
}

# 各ツールに対してターゲットを作成
resource "aws_bedrockagentcore_gateway_target" "tools" {
  for_each = local.tools

  name               = "${var.project_name}-${replace(each.key, "_", "-")}"
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id

  description = each.value.description

  # Gateway の IAM ロールを使用して Lambda を呼び出す
  credential_provider_configuration {
    gateway_iam_role {}
  }

  # MCP Target 設定
  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.mcp_tools.arn

        tool_schema {
          inline_payload {
            name        = each.key
            description = each.value.description

            input_schema {
              type        = each.value.input_schema.type
              description = each.value.input_schema.description

              # プロパティがある場合のみ property ブロックを追加
              dynamic "property" {
                for_each = lookup(each.value.input_schema, "properties", {})
                content {
                  name        = property.value.name
                  type        = property.value.type
                  description = property.value.description
                  required    = lookup(property.value, "required", false)
                }
              }
            }
          }
        }
      }
    }
  }
}
