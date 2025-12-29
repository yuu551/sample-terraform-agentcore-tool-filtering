# AgentCore Gateway with Permission-based Tool Filtering

AWS Bedrock AgentCore Gateway を使用した、権限ベースのツールフィルタリング機能を持つ MCP Server のサンプル実装です。

## 概要

このプロジェクトは、Response Interceptor でユーザーの権限に基づいてツールの一覧をフィルタリングする機能を実装しています。

## アーキテクチャ

```
┌─────────────┐     ┌──────────────────────┐     ┌─────────────────────┐
│   Client    │────▶│  AgentCore Gateway   │────▶│  Response Interceptor│
│ (Agent/App) │     │   (MCP Protocol)     │     │      Lambda         │
└─────────────┘     └──────────────────────┘     └─────────────────────┘
                              │                            │
                              │ JWT認証                    │ tools/list
                              ▼                            │ フィルタリング
                    ┌──────────────────┐                   │
                    │  Cognito User    │                   │
                    │     Pool         │                   │
                    │  ┌────────────┐  │                   │
                    │  │  Groups:   │  │                   │
                    │  │  - admin   │  │◀──────────────────┘
                    │  │  - power   │  │   グループ情報取得
                    │  │  - reader  │  │
                    │  │  - guest   │  │
                    │  └────────────┘  │
                    └──────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  Gateway Targets │
                    │  (8 Tools)       │
                    │  ┌────────────┐  │
                    │  │Lambda Func │  │
                    │  └────────────┘  │
                    └──────────────────┘
```

## 機能

- **MCP Protocol サポート**: AgentCore Gateway が MCP Server として機能
- **JWT 認証**: Cognito User Pool による認証
- **Response Interceptor**: `tools/list` レスポンスを権限に基づいてフィルタリング
- **グループベース権限**: Cognito Groups でユーザー権限を管理

## 権限マッピング

| グループ | アクセス可能なツール |
|---------|---------------------|
| `admin` | 全ツール (`*`) |
| `power_user` | `search`, `read`, `write`, `list` |
| `reader` | `search`, `read`, `list` |
| `guest` | `list` のみ |

## 提供ツール

| ツール名 | 説明 | カテゴリ |
|---------|------|---------|
| `list_documents` | ドキュメント一覧取得 | list |
| `search_documents` | ドキュメント検索 | search |
| `read_document` | ドキュメント読み取り | read |
| `write_document` | ドキュメント作成/更新 | write |
| `delete_document` | ドキュメント削除 | admin |
| `list_users` | ユーザー一覧取得 | list |
| `read_user` | ユーザー詳細取得 | read |
| `admin_reset` | システムリセット | admin |

## 前提条件

- Terraform >= 1.5.0
- AWS CLI (設定済み)
- AWS アカウント (Bedrock AgentCore が利用可能なリージョン)

## ファイル構成

```
.
├── README.md              # このファイル
├── TESTING.md             # 検証手順書
├── cognito.tf             # Cognito User Pool, Groups, Client
├── gateway.tf             # AgentCore Gateway, Interceptor, Targets
├── lambda.tf              # Lambda 関数定義
├── lambda/
│   ├── interceptor/
│   │   └── handler.py     # Response Interceptor 実装
│   └── mcp_tools/
│       └── handler.py     # MCP ツール実装
├── outputs.tf             # 出力定義
├── variables.tf           # 変数定義
└── versions.tf            # Provider 設定
```

## デプロイ

```bash
# 1. 初期化
terraform init

# 2. プレビュー
terraform plan

# 3. デプロイ
terraform apply

# 4. 出力確認
terraform output
```

## 変数

| 変数名 | 説明 | デフォルト |
|--------|------|-----------|
| `aws_region` | デプロイリージョン | `us-east-1` |
| `environment` | 環境名 | `dev` |
| `project_name` | プロジェクト名 | `agentcore-demo` |
| `tool_permissions` | グループ別ツール権限 | 上記参照 |

## カスタマイズ

### 権限マッピングの変更

`variables.tf` の `tool_permissions` を編集:

```hcl
variable "tool_permissions" {
  default = {
    "admin"      = ["*"]
    "power_user" = ["search", "read", "write", "list"]
    "reader"     = ["search", "read", "list"]
    "guest"      = ["list"]
    # 新しいグループを追加
    "custom_role" = ["search", "read"]
  }
}
```

### ツールの追加

1. `gateway.tf` の `locals.tools` に新しいツール定義を追加
2. `lambda/mcp_tools/handler.py` に対応する関数を実装

## クリーンアップ

```bash
terraform destroy
```