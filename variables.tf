variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "agentcore-demo"
}

# ツールと権限のマッピング設定
variable "tool_permissions" {
  description = "Mapping of Cognito groups to allowed tools"
  type        = map(list(string))
  default = {
    "admin"      = ["*"]                               # 全ツールアクセス可
    "power_user" = ["search", "read", "write", "list"] # 読み書き可
    "reader"     = ["search", "read", "list"]          # 読み取り専用
    "guest"      = ["list"]                            # リスト表示のみ
  }
}
