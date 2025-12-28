"""
Response Interceptor Lambda for AgentCore Gateway

Cognitoのグループ情報に基づいて tools/list のレスポンスをフィルタリングする
"""

import json
import logging
import base64
import os
from typing import Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# 環境変数からツール権限マッピングを取得
TOOL_PERMISSIONS = json.loads(os.environ.get('TOOL_PERMISSIONS', '{}'))


def decode_jwt_payload(token: str) -> dict:
    """JWTのペイロード部分をデコード（署名検証はGatewayが実施済み）"""
    try:
        # Bearer プレフィックスを除去
        if token.startswith('Bearer '):
            token = token[7:]

        # JWTのペイロード部分を取得（ヘッダー.ペイロード.署名）
        parts = token.split('.')
        if len(parts) != 3:
            return {}

        # Base64デコード（パディング調整）
        payload = parts[1]
        padding = 4 - len(payload) % 4
        if padding != 4:
            payload += '=' * padding

        decoded = base64.urlsafe_b64decode(payload)
        return json.loads(decoded)
    except Exception as e:
        logger.warning(f"Failed to decode JWT: {e}")
        return {}


def get_user_groups(event: dict) -> list[str]:
    """リクエストからユーザーのCognitoグループを取得"""
    try:
        gateway_request = event.get('mcp', {}).get('gatewayRequest', {})
        headers = gateway_request.get('headers', {})

        # Authorization ヘッダーから JWT を取得
        auth_header = headers.get('Authorization', '') or headers.get('authorization', '')
        if not auth_header:
            logger.info("No Authorization header found")
            return ['guest']

        payload = decode_jwt_payload(auth_header)

        # Cognito の cognito:groups クレームを取得
        groups = payload.get('cognito:groups', [])
        if not groups:
            # カスタム属性もチェック
            custom_groups = payload.get('custom:groups', '')
            if custom_groups:
                groups = custom_groups.split(',')

        logger.info(f"User groups: {groups}")
        return groups if groups else ['guest']

    except Exception as e:
        logger.error(f"Error getting user groups: {e}")
        return ['guest']


def get_allowed_tools(groups: list[str]) -> set[str]:
    """グループに基づいて許可されたツール名のセットを返す"""
    allowed = set()

    for group in groups:
        group_tools = TOOL_PERMISSIONS.get(group, [])
        if '*' in group_tools:
            # 全ツールアクセス可
            return {'*'}
        allowed.update(group_tools)

    # デフォルトでguestの権限
    if not allowed:
        allowed.update(TOOL_PERMISSIONS.get('guest', ['list']))

    return allowed


def filter_tools_response(response_body: dict, allowed_tools: set[str]) -> dict:
    """tools/list レスポンスをフィルタリング"""
    if '*' in allowed_tools:
        return response_body

    result = response_body.get('result', {})
    tools = result.get('tools', [])

    filtered_tools = []
    for tool in tools:
        tool_name = tool.get('name', '')

        # AgentCore Gateway のツール名形式: {target-name}___{tool-name}
        # 例: agentcore-demo-list-documents___list_documents
        if '___' in tool_name:
            actual_tool_name = tool_name.split('___')[-1]  # list_documents
        else:
            actual_tool_name = tool_name

        # ツール名のカテゴリでマッチング（例: list_documents -> list）
        tool_category = actual_tool_name.split('_')[0] if '_' in actual_tool_name else actual_tool_name

        logger.info(f"Checking tool: {tool_name} -> actual: {actual_tool_name} -> category: {tool_category}")

        if actual_tool_name in allowed_tools or tool_category in allowed_tools:
            filtered_tools.append(tool)
            logger.info(f"Tool allowed: {tool_name}")
        else:
            logger.info(f"Tool filtered out: {tool_name}")

    # フィルタリング後のレスポンスを構築
    filtered_response = response_body.copy()
    filtered_response['result'] = result.copy()
    filtered_response['result']['tools'] = filtered_tools

    return filtered_response


def lambda_handler(event: dict, context: Any) -> dict:
    """
    AgentCore Gateway Response Interceptor

    tools/list のレスポンスをユーザーの権限に基づいてフィルタリング
    """
    logger.info(f"Interceptor invoked with event keys: {list(event.keys())}")

    mcp_data = event.get('mcp', {})

    # REQUEST or RESPONSE インターセプターかを判定
    gateway_response = mcp_data.get('gatewayResponse')

    if gateway_response is None:
        # REQUEST インターセプター: パススルー
        logger.info("Processing REQUEST interceptor - passing through")
        gateway_request = mcp_data.get('gatewayRequest', {})
        return {
            "interceptorOutputVersion": "1.0",
            "mcp": {
                "transformedGatewayRequest": {
                    "body": gateway_request.get('body', {})
                }
            }
        }

    # RESPONSE インターセプター
    logger.info("Processing RESPONSE interceptor")

    gateway_request = mcp_data.get('gatewayRequest', {})
    request_body = gateway_request.get('body', {})
    response_body = gateway_response.get('body', {})

    # MCP メソッドを確認
    mcp_method = request_body.get('method', '')
    logger.info(f"MCP method: {mcp_method}")

    # tools/list 以外はパススルー
    if mcp_method != 'tools/list':
        logger.info(f"Method '{mcp_method}' - passing through unchanged")
        return {
            "interceptorOutputVersion": "1.0",
            "mcp": {
                "transformedGatewayResponse": {
                    "statusCode": gateway_response.get('statusCode', 200),
                    "body": response_body
                }
            }
        }

    # tools/list の場合: 権限に基づいてフィルタリング
    logger.info("Filtering tools/list response based on user permissions")

    # ユーザーのグループを取得
    user_groups = get_user_groups(event)

    # 許可されたツールを取得
    allowed_tools = get_allowed_tools(user_groups)
    logger.info(f"Allowed tools for groups {user_groups}: {allowed_tools}")

    # レスポンスをフィルタリング
    filtered_body = filter_tools_response(response_body, allowed_tools)

    original_count = len(response_body.get('result', {}).get('tools', []))
    filtered_count = len(filtered_body.get('result', {}).get('tools', []))
    logger.info(f"Tools filtered: {original_count} -> {filtered_count}")

    return {
        "interceptorOutputVersion": "1.0",
        "mcp": {
            "transformedGatewayResponse": {
                "statusCode": gateway_response.get('statusCode', 200),
                "body": filtered_body
            }
        }
    }
