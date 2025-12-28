# =============================================================================
# Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Cognito Outputs
# -----------------------------------------------------------------------------

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_endpoint" {
  description = "Cognito User Pool endpoint"
  value       = aws_cognito_user_pool.main.endpoint
}

output "cognito_client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.gateway.id
}

# Client Secret は無効化 (CLI テスト用)
# output "cognito_client_secret" {
#   description = "Cognito User Pool Client Secret"
#   value       = aws_cognito_user_pool_client.gateway.client_secret
#   sensitive   = true
# }

output "cognito_domain" {
  description = "Cognito domain for OAuth"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "cognito_token_endpoint" {
  description = "Cognito token endpoint"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/token"
}

# -----------------------------------------------------------------------------
# AgentCore Gateway Outputs
# -----------------------------------------------------------------------------

output "gateway_id" {
  description = "AgentCore Gateway ID"
  value       = aws_bedrockagentcore_gateway.main.gateway_id
}

output "gateway_arn" {
  description = "AgentCore Gateway ARN"
  value       = aws_bedrockagentcore_gateway.main.gateway_arn
}

output "gateway_url" {
  description = "AgentCore Gateway URL (MCP endpoint)"
  value       = aws_bedrockagentcore_gateway.main.gateway_url
}

# -----------------------------------------------------------------------------
# Lambda Outputs
# -----------------------------------------------------------------------------

output "interceptor_lambda_arn" {
  description = "Response Interceptor Lambda ARN"
  value       = aws_lambda_function.interceptor.arn
}

output "mcp_tools_lambda_arn" {
  description = "MCP Tools Lambda ARN"
  value       = aws_lambda_function.mcp_tools.arn
}

# -----------------------------------------------------------------------------
# Gateway Targets
# -----------------------------------------------------------------------------

output "gateway_targets" {
  description = "Gateway Target IDs"
  value       = { for k, v in aws_bedrockagentcore_gateway_target.tools : k => v.target_id }
}

# -----------------------------------------------------------------------------
# Usage Information
# -----------------------------------------------------------------------------

output "usage_info" {
  description = "How to use the deployed gateway"
  value       = <<-EOT

    =====================================================
    AgentCore Gateway with Permission-based Tool Filtering
    =====================================================

    Gateway URL: ${aws_bedrockagentcore_gateway.main.gateway_url}

    ## 1. Get Access Token

    # User Password Flow (for testing):
    aws cognito-idp admin-initiate-auth \
      --user-pool-id ${aws_cognito_user_pool.main.id} \
      --client-id ${aws_cognito_user_pool_client.gateway.id} \
      --auth-flow ADMIN_USER_PASSWORD_AUTH \
      --auth-parameters USERNAME=<email>,PASSWORD=<password>

    ## 2. Call MCP tools/list

    curl -X POST "${aws_bedrockagentcore_gateway.main.gateway_url}/mcp" \
      -H "Authorization: Bearer <ACCESS_TOKEN>" \
      -H "Content-Type: application/json" \
      -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}'

    ## 3. User Groups and Tool Access

    | Group      | Allowed Tools                   |
    |------------|--------------------------------|
    | admin      | All tools (*)                  |
    | power_user | search, read, write, list      |
    | reader     | search, read, list             |
    | guest      | list only                      |

    ## 4. Create Test Users

    # Create user
    aws cognito-idp admin-create-user \
      --user-pool-id ${aws_cognito_user_pool.main.id} \
      --username testuser@example.com \
      --user-attributes Name=email,Value=testuser@example.com \
      --temporary-password TempPass123!

    # Add to admin group
    aws cognito-idp admin-add-user-to-group \
      --user-pool-id ${aws_cognito_user_pool.main.id} \
      --username testuser@example.com \
      --group-name admin

    ## 5. Set permanent password

    aws cognito-idp admin-set-user-password \
      --user-pool-id ${aws_cognito_user_pool.main.id} \
      --username testuser@example.com \
      --password YourPassword123! \
      --permanent

  EOT
}
