"""
MCP Server Target Lambda

AgentCore Gateway から呼び出されるツールを提供するサンプル実装
"""

import json
import logging
from typing import Any
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AgentCore Gateway のツール名デリミタ
TOOL_NAME_DELIMITER = "___"


# =============================================================================
# ツール定義
# =============================================================================

TOOLS = {
    "list_documents": {
        "description": "List available documents",
        "category": "list"
    },
    "search_documents": {
        "description": "Search documents by query",
        "category": "search"
    },
    "read_document": {
        "description": "Read a specific document",
        "category": "read"
    },
    "write_document": {
        "description": "Create or update a document",
        "category": "write"
    },
    "delete_document": {
        "description": "Delete a document",
        "category": "admin"
    },
    "list_users": {
        "description": "List all users",
        "category": "list"
    },
    "read_user": {
        "description": "Get user details",
        "category": "read"
    },
    "admin_reset": {
        "description": "Reset system (admin only)",
        "category": "admin"
    }
}


# =============================================================================
# ツール実装
# =============================================================================

def list_documents(params: dict) -> dict:
    """ドキュメント一覧を返す"""
    return {
        "documents": [
            {"id": "doc1", "title": "Getting Started", "updated": "2024-01-15"},
            {"id": "doc2", "title": "API Reference", "updated": "2024-01-20"},
            {"id": "doc3", "title": "Best Practices", "updated": "2024-01-25"}
        ],
        "total": 3
    }


def search_documents(params: dict) -> dict:
    """ドキュメント検索"""
    query = params.get("query", "")
    return {
        "query": query,
        "results": [
            {"id": "doc1", "title": "Getting Started", "score": 0.95},
            {"id": "doc2", "title": "API Reference", "score": 0.82}
        ],
        "total": 2
    }


def read_document(params: dict) -> dict:
    """ドキュメント読み取り"""
    doc_id = params.get("document_id", "unknown")
    return {
        "id": doc_id,
        "title": f"Document {doc_id}",
        "content": f"This is the content of document {doc_id}.",
        "metadata": {
            "author": "system",
            "created": "2024-01-01",
            "updated": "2024-01-15"
        }
    }


def write_document(params: dict) -> dict:
    """ドキュメント作成/更新"""
    doc_id = params.get("document_id", f"doc_{datetime.now().timestamp()}")
    title = params.get("title", "Untitled")
    content = params.get("content", "")

    return {
        "success": True,
        "id": doc_id,
        "title": title,
        "message": f"Document '{title}' has been saved."
    }


def delete_document(params: dict) -> dict:
    """ドキュメント削除"""
    doc_id = params.get("document_id", "unknown")
    return {
        "success": True,
        "id": doc_id,
        "message": f"Document {doc_id} has been deleted."
    }


def list_users(params: dict) -> dict:
    """ユーザー一覧"""
    return {
        "users": [
            {"id": "user1", "name": "Alice", "role": "admin"},
            {"id": "user2", "name": "Bob", "role": "power_user"},
            {"id": "user3", "name": "Charlie", "role": "reader"}
        ],
        "total": 3
    }


def read_user(params: dict) -> dict:
    """ユーザー詳細"""
    user_id = params.get("user_id", "unknown")
    return {
        "id": user_id,
        "name": f"User {user_id}",
        "email": f"{user_id}@example.com",
        "role": "reader",
        "created": "2024-01-01"
    }


def admin_reset(params: dict) -> dict:
    """システムリセット（管理者専用）"""
    target = params.get("target", "cache")
    return {
        "success": True,
        "target": target,
        "message": f"System {target} has been reset.",
        "timestamp": datetime.now().isoformat()
    }


# ツール名と関数のマッピング
TOOL_HANDLERS = {
    "list_documents": list_documents,
    "search_documents": search_documents,
    "read_document": read_document,
    "write_document": write_document,
    "delete_document": delete_document,
    "list_users": list_users,
    "read_user": read_user,
    "admin_reset": admin_reset
}


def get_tool_name_from_context(context: Any) -> str:
    """
    AgentCore Gateway の context からツール名を取得

    ツール名形式: {target_name}___{tool_name}
    例: agentcore-demo-list-documents___list_documents -> list_documents
    """
    try:
        if hasattr(context, 'client_context') and context.client_context:
            custom = context.client_context.custom
            if custom and 'bedrockAgentCoreToolName' in custom:
                original_tool_name = custom['bedrockAgentCoreToolName']
                logger.info(f"Original tool name from context: {original_tool_name}")

                # デリミタでプレフィックスを除去
                if TOOL_NAME_DELIMITER in original_tool_name:
                    tool_name = original_tool_name.split(TOOL_NAME_DELIMITER)[-1]
                    logger.info(f"Extracted tool name: {tool_name}")
                    return tool_name
                return original_tool_name
    except Exception as e:
        logger.warning(f"Failed to get tool name from context: {e}")

    return ""


def lambda_handler(event: dict, context: Any) -> dict:
    """
    MCP Server Target Lambda Handler

    AgentCore Gateway からツール呼び出しを受け取り、結果を返す
    """
    logger.info(f"Tool invocation received: {json.dumps(event)}")

    # context からツール名を取得 (AgentCore Gateway の標準方式)
    tool_name = get_tool_name_from_context(context)

    # context から取得できない場合のフォールバック
    if not tool_name:
        logger.warning("Could not get tool name from context, trying fallback methods")

        # event から _tool_name を確認
        tool_name = event.get('_tool_name', '')

        # event のキーからツール名を推測
        if not tool_name:
            for key in event.keys():
                if key in TOOL_HANDLERS:
                    tool_name = key
                    break

    logger.info(f"Tool name resolved: {tool_name}")

    # ツールハンドラを取得
    handler = TOOL_HANDLERS.get(tool_name)

    if not handler:
        logger.error(f"Unknown tool: {tool_name}")
        return {
            "error": f"Unknown tool: {tool_name}",
            "available_tools": list(TOOL_HANDLERS.keys())
        }

    try:
        # event がそのままツールのパラメータ
        result = handler(event)
        logger.info(f"Tool {tool_name} executed successfully")
        return result

    except Exception as e:
        logger.error(f"Tool execution failed: {e}")
        return {
            "error": str(e),
            "tool": tool_name
        }
