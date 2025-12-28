# =============================================================================
# Cognito User Pool - 認証基盤
# =============================================================================

resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-user-pool"

  # パスワードポリシー
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  # ユーザー属性
  schema {
    name                     = "email"
    attribute_data_type      = "String"
    mutable                  = true
    required                 = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  # カスタム属性: 追加の権限制御用
  schema {
    name                     = "allowed_tools"
    attribute_data_type      = "String"
    mutable                  = true
    required                 = false
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  # 自動検証設定
  auto_verified_attributes = ["email"]

  # アカウント回復設定
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # 管理者がユーザー作成可能
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  tags = {
    Name = "${var.project_name}-user-pool"
  }
}

# =============================================================================
# Cognito User Pool Groups - 権限グループ
# =============================================================================

resource "aws_cognito_user_group" "admin" {
  name         = "admin"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Full access to all tools"
  precedence   = 1
}

resource "aws_cognito_user_group" "power_user" {
  name         = "power_user"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Read/write access to tools"
  precedence   = 2
}

resource "aws_cognito_user_group" "reader" {
  name         = "reader"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Read-only access to tools"
  precedence   = 3
}

resource "aws_cognito_user_group" "guest" {
  name         = "guest"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Limited access - list only"
  precedence   = 4
}

# =============================================================================
# Cognito User Pool Client - AgentCore Gateway用
# =============================================================================

resource "aws_cognito_user_pool_client" "gateway" {
  name         = "${var.project_name}-gateway-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # クライアント認証設定 (CLI テスト用に Secret なし)
  generate_secret     = false
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_ADMIN_USER_PASSWORD_AUTH"
  ]

  # OAuth 設定 (Authorization Code Flow)
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://localhost/callback"]

  # トークン有効期限
  access_token_validity  = 1  # 1時間
  id_token_validity      = 1  # 1時間
  refresh_token_validity = 30 # 30日

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # ID Token にグループ情報を含める
  read_attributes  = ["email", "custom:allowed_tools"]
  write_attributes = ["email", "custom:allowed_tools"]
}

# =============================================================================
# Cognito User Pool Domain - OAuth エンドポイント用
# =============================================================================

resource "random_string" "cognito_domain_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-${random_string.cognito_domain_suffix.result}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# =============================================================================
# Cognito Resource Server - スコープ定義
# =============================================================================

resource "aws_cognito_resource_server" "gateway" {
  identifier   = "agentcore-gateway"
  name         = "AgentCore Gateway"
  user_pool_id = aws_cognito_user_pool.main.id

  scope {
    scope_name        = "tools.read"
    scope_description = "Read tools"
  }

  scope {
    scope_name        = "tools.write"
    scope_description = "Write tools"
  }

  scope {
    scope_name        = "tools.admin"
    scope_description = "Admin tools"
  }
}
