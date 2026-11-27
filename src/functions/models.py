"""数据模型：请求/响应校验 + token 表条目结构约束。"""

import json

from pydantic import BaseModel, Field, ValidationError, field_validator


def api_response(status_code: int, body_model: BaseModel) -> dict:
    """构造接入层响应（网关触发器规范：statusCode + headers + body）。

    body 序列化为 JSON 字符串，符合网关代理集成约定。
    """
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, X-Apig-AppCode",
        },
        "body": json.dumps(body_model.model_dump(mode="json"), ensure_ascii=False),
    }


class TokenExchangeRequest(BaseModel):
    """POST /token 请求体模型。"""

    token: str = Field(
        ...,
        description="Application token to exchange (URL-safe base64 string)",
        min_length=32,
        max_length=100,
    )

    @field_validator("token")
    @classmethod
    def validate_token_format(cls, v: str) -> str:
        # URL-safe base64 字符集：A-Z / a-z / 0-9 / - / _
        if not all(c.isalnum() or c in "-_" for c in v):
            raise ValueError("Token format validation failed.")
        return v


class TokenGenerateResponse(BaseModel):
    """GET /token 响应模型。"""

    token: str = Field(
        ..., description="Generated application token (URL-safe base64 string)"
    )
    expires_at: int = Field(
        ..., description="Unix epoch timestamp when token expires"
    )


class TokenExchangeResponse(BaseModel):
    """POST /token 响应模型。"""

    presigned_url: str = Field(
        ..., description="Signed URL with N-second expiration"
    )


class ErrorResponse(BaseModel):
    """错误响应统一模型。"""

    error: str = Field(..., description="Human-readable error message")


class TokenItem(BaseModel):
    """token 表条目模型（宽表键：token）。

    字段语义：valid 为单次使用标志（条件更新由 true 置 false 实现防重用），
    ttl 为条目过期时间戳，obs_uri 为目标对象地址。
    """

    token: str = Field(
        ..., description="URL-safe base64 format security token string"
    )
    valid: bool = Field(
        ...,
        description="Token validity state - true for valid, false for used",
    )
    created_at: int = Field(
        ..., description="Unix epoch timestamp of token creation"
    )
    ttl: int = Field(
        ..., description="Unix epoch timestamp for TTL (created_at + 3600)"
    )
    obs_uri: str = Field(
        ...,
        description="Target object URI in format obs://bucket/key",
        pattern=r"^obs://[a-z0-9][a-z0-9\-]{1,61}[a-z0-9]/.*$",
    )

    @classmethod
    def create_new_token(
        cls, token: str, created_at: int, ttl: int, obs_uri: str
    ) -> tuple["TokenItem | None", "ErrorResponse | None"]:
        try:
            item = cls(
                token=token,
                valid=True,
                created_at=created_at,
                ttl=ttl,
                obs_uri=obs_uri,
            )
            return item, None
        except ValidationError:
            return None, ErrorResponse(error="Failed to generate token.")

    @classmethod
    def from_table_item(
        cls, item_dict: dict
    ) -> tuple["TokenItem | None", "ErrorResponse | None"]:
        try:
            return cls(**item_dict), None
        except ValidationError:
            return None, ErrorResponse(error="Failed to validate token.")
