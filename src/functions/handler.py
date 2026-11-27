"""函数入口：单次使用 token 生成 + 交换。

业务逻辑：
  1. GET  /token —— 生成 URL-safe 随机 token，落宽表（含 TTL 属性 ttl）
  2. POST /token —— 以「条件更新」原子地把 valid 由 true 置 false（防重用），
                    再签发目标对象的短期签名 URL

适配要点：
  - 依赖收敛到标准库 + 宽表协议客户端 + 对象存储客户端；运行环境已内置对象
    存储客户端，无需随包携带
  - 宽表数据面鉴权用实例账号 rwuser + 实例管理员密码（不接受临时凭证，
    也不支持 securityToken）
  - 对象存储客户端所需的临时凭证只经函数入参 context 注入，不读环境变量
  - 接入层已强制应用认证，函数侧不再重复验签
"""

import json
import logging
import os
import secrets
import time

import boto3
from botocore.exceptions import ClientError
from obs import ObsClient
from pydantic import ValidationError

from models import (
    ErrorResponse,
    TokenItem,
    TokenExchangeRequest,
    TokenExchangeResponse,
    TokenGenerateResponse,
    api_response,
)

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)

# ----- 全局客户端（惰性初始化，便于单测注入） -----
dynamodb = None
obs_client = None
signer_obs = None
_obs_security_token = None


def _context_credentials(context):
    """从函数入参 context 取委托临时凭证（唯一来源）。"""
    ak = sk = token = None
    if context is not None:
        try:
            ak = context.getSecurityAccessKey()
            sk = context.getSecuritySecretKey()
            token = context.getSecurityToken()
        except Exception:
            logger.warning("Delegation credentials unavailable", exc_info=True)
    return ak, sk, token


def setup_clients(context):
    """惰性初始化宽表 / 对象存储客户端。

    obs_client 用委托临时凭据（SDK 直连有效）；signer_obs 用永久 AK/SK
    （用于 URL 预签名——委托临时 AK 生成的 URL 在对象存储签名校验层查无此人，
    实测 InvalidAccessKeyId；永久 AK 全程用于 IaC 管理 OBS，兼容层一定认）。
    """
    global dynamodb, obs_client, signer_obs, _obs_security_token
    region = os.environ.get("REGION", "cn-north-4")

    if dynamodb is None:
        endpoint = os.environ.get("GEMINIDB_ENDPOINT", "")
        port = os.environ.get("GEMINIDB_PORT", "80")
        if endpoint:
            # 兼容协议接口：以实例账号 + 实例密码作静态凭据做签名；
            # 区域仅参与签名，不参与路由。
            dynamodb = boto3.resource(
                "dynamodb",
                endpoint_url="http://%s:%s" % (endpoint, port),
                region_name=region,
                aws_access_key_id=os.environ.get("GEMINIDB_USER", "rwuser"),
                aws_secret_access_key=os.environ.get("GEMINIDB_PASSWORD", ""),
            )
        else:
            raise RuntimeError("GEMINIDB_ENDPOINT is not configured")

    if obs_client is None:
        ak, sk, token = _context_credentials(context)
        _obs_security_token = token
        server = "https://obs.%s.myhuaweicloud.com" % region
        if ak and sk:
            obs_client = ObsClient(
                access_key_id=ak,
                secret_access_key=sk,
                security_token=token,
                server=server,
            )
        else:
            # 无线索时交由运行环境默认链路解析
            obs_client = ObsClient(server=server)

    if signer_obs is None:
        # 永久 AK/SK 专用签名客户端：仅用于 URL 预签名（不透出、不留日志）
        s_ak = os.environ.get("OBS_SIGNER_AK", "")
        s_sk = os.environ.get("OBS_SIGNER_SK", "")
        server = "https://obs.%s.myhuaweicloud.com" % region
        if s_ak and s_sk:
            signer_obs = ObsClient(
                access_key_id=s_ak,
                secret_access_key=s_sk,
                server=server,
            )


def _ensure_table():
    """建表兜底：兼容协议接口需显式建表（实测不支持首写自动建表）。

    GeminiDB 兼容 DynamoDB 接口的 create_table 要求携带 ProvisionedThroughput
    （仅为协议兼容的必填项），缺省会直接被服务端拒绝。
    建表为异步操作，需轮询等待表进入 ACTIVE 后才能写入。
    """
    table_name = os.environ.get("TABLE_NAME", "single-use-tokens")
    client = dynamodb.meta.client
    try:
        client.describe_table(TableName=table_name)
        return
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "")
        msg = e.response.get("Error", {}).get("Message", "")
        logger.warning("describe_table: %s %s", code, msg)
        # 认证/权限类错误直接放弃（非表缺失问题）；其余一律尝试建表
        if code in ("AccessDeniedException", "UnrecognizedClientException",
                    "InvalidSignatureException", "ExpiredTokenException"):
            raise
    try:
        client.create_table(
            TableName=table_name,
            KeySchema=[{"AttributeName": "token", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "token", "AttributeType": "S"}],
            ProvisionedThroughput={
                "ReadCapacityUnits": 5,
                "WriteCapacityUnits": 5,
            },
        )
        logger.info("Created table %s, waiting for ACTIVE", table_name)
        for _ in range(15):
            time.sleep(1)
            try:
                resp = client.describe_table(TableName=table_name)
                status = resp.get("Table", {}).get("TableStatus")
                if status == "ACTIVE":
                    logger.info("Table %s is ACTIVE", table_name)
                    return
            except ClientError:
                pass
        logger.warning("Table %s not ACTIVE after polling", table_name)
    except ClientError as e:
        err = e.response.get("Error", {})
        logger.error(
            "create_table failed: %s: %s",
            err.get("Code", ""),
            err.get("Message", ""),
            exc_info=True,
        )
        raise


# ----- 路由 -----

def route(event):
    """按请求方法与路径分发。"""
    http_method = (event.get("httpMethod") or "GET").upper()
    path = (event.get("path") or "/").rstrip("/") or "/"
    if http_method == "GET" and path == "/token":
        return "generate_token", None
    if http_method == "POST" and path == "/token":
        return "exchange_token", None
    return "", api_response(
        404, ErrorResponse(error="Not Found: %s %s" % (http_method, path))
    )


def _parse_body(event):
    raw = event.get("body")
    if isinstance(raw, dict):
        return raw, None
    if isinstance(raw, (bytes, bytearray)):
        raw = raw.decode("utf-8", errors="replace")
    if isinstance(raw, str):
        candidates = [raw]
        # 网关代理集成可能按 isBase64Encoded 把 body 做 base64 编码
        if event.get("isBase64Encoded"):
            import base64 as _b64

            try:
                candidates.append(_b64.b64decode(raw).decode("utf-8", errors="replace"))
            except Exception:
                pass
        # 某些网关会整体转义 JSON（{"a":1} -> {\"a\":1}）
        if raw.startswith('\\"') or ("\\\"" in raw[:20]):
            try:
                candidates.append(raw.encode("utf-8").decode("unicode_escape"))
            except Exception:
                pass
        for cand in candidates:
            try:
                return json.loads(cand), None
            except (json.JSONDecodeError, TypeError):
                continue
        return None, api_response(
            400,
            ErrorResponse(
                error="Invalid request format: request body must be valid JSON (got: %s)"
                % raw[:200]
            ),
        )
    return None, api_response(
        400, ErrorResponse(error="Invalid request format: missing body")
    )


# ----- 业务处理 -----

def generate_token(event, context):
    """生成单次使用 token。"""
    logger.info("Token generation requested")
    table_name = os.environ.get("TABLE_NAME", "single-use-tokens")
    obs_bucket = os.environ.get("OBS_BUCKET_NAME", "")
    obs_key = os.environ.get("OBS_OBJECT_KEY", "sample-image.png")
    ttl_seconds = int(os.environ.get("TOKEN_TTL_SECONDS", "3600"))

    token = secrets.token_urlsafe(32)
    created_at = int(time.time())
    expires_at = created_at + ttl_seconds

    item, error_response = TokenItem.create_new_token(
        token=token,
        created_at=created_at,
        ttl=expires_at,
        obs_uri="obs://%s/%s" % (obs_bucket, obs_key),
    )
    if error_response:
        logger.error("Token payload rejected by validation")
        return api_response(500, error_response)

    try:
        dynamodb.Table(table_name).put_item(Item=item.model_dump())
    except ClientError as e:
        err = e.response.get("Error", {})
        detail = "%s: %s" % (
            err.get("Code", "Unknown"),
            err.get("Message", ""),
        )
        logger.error("put_item failed: %s", detail, exc_info=True)
        return api_response(
            500,
            ErrorResponse(
                error="Failed to generate token. (%s)" % detail[:200]
            ),
        )

    return api_response(200, TokenGenerateResponse(token=token, expires_at=expires_at))


def exchange_token(event, context):
    """用 token 换短期签名 URL。"""
    logger.info("Token exchange requested")
    table_name = os.environ.get("TABLE_NAME", "single-use-tokens")
    expires_in = int(os.environ.get("PRESIGNED_URL_EXPIRATION", "300"))

    body, error_response = _parse_body(event)
    if error_response:
        return error_response

    try:
        token_str = TokenExchangeRequest(**body).token
    except ValidationError as e:
        first = e.errors()[0]
        field = first.get("loc", ["unknown"])[0]
        return api_response(
            400,
            ErrorResponse(
                error="Invalid request format: field '%s' %s"
                % (field, first.get("msg", "validation failed"))
            ),
        )

    table = dynamodb.Table(table_name)
    try:
        response = table.get_item(Key={"token": token_str})
    except ClientError:
        logger.error("get_item failed", exc_info=True)
        return api_response(500, ErrorResponse(error="Failed to validate token."))

    if "Item" not in response:
        return api_response(
            403, ErrorResponse(error="Token is invalid, expired, or already used")
        )

    item, error_response = TokenItem.from_table_item(response["Item"])
    if error_response:
        return api_response(500, error_response)
    if not item.valid:
        return api_response(
            403, ErrorResponse(error="Token is invalid, expired, or already used")
        )

    # 关键安全机制：条件更新（valid 由 true 置 false）；条件失败即并发重用
    try:
        table.update_item(
            Key={"token": token_str},
            UpdateExpression="SET valid = :false",
            ConditionExpression="valid = :true",
            ExpressionAttributeValues={":false": False, ":true": True},
        )
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "Unknown")
        if code == "ConditionalCheckFailedException":
            logger.warning("Token already consumed (concurrent request)")
            return api_response(
                403,
                ErrorResponse(error="Token is invalid, expired, or already used"),
            )
        logger.error("update_item failed", exc_info=True)
        return api_response(500, ErrorResponse(error="Failed to process token."))

    obs_path = item.obs_uri.replace("obs://", "", 1)
    bucket, _, key = obs_path.partition("/")
    if not key:
        return api_response(500, ErrorResponse(error="Failed to generate download URL."))

    # ---- 诊断：委托临时凭据对 OBS 数据面是否有效 ----
    try:
        probe = obs_client.getObject(bucket, key, loadStreamInMemory=True)
        probe_status = getattr(probe, "status", None)
        probe_err = getattr(probe, "errorCode", "")
        if probe_status is not None and probe_status < 300:
            logger.info("OBS data-plane probe OK: status=%s", probe_status)
        else:
            detail = "status=%s errorCode=%s %s" % (
                probe_status,
                probe_err,
                getattr(probe, "errorMessage", ""),
            )
            logger.error("OBS data-plane probe FAILED: %s", detail)
            return api_response(
                500,
                ErrorResponse(
                    error="OBS temp-cred direct read FAILED (%s)" % detail[:200]
                ),
            )
    except Exception as pe:
        logger.error("OBS data-plane probe raised: %s %s",
                     type(pe).__name__, str(pe), exc_info=True)
        return api_response(
            500,
            ErrorResponse(
                error="OBS temp-cred direct read raised (%s: %s)"
                % (type(pe).__name__, str(pe)[:150])
            ),
        )

    try:
        # URL 预签名：必须用永久 AK/SK 签名客户端（signer_obs）。
        # 委托临时 AK 生成的 URL 在对象存储签名校验层报 InvalidAccessKeyId
        # （实测 4 种组合均失败），永久 AK 全程用于 IaC 管理 OBS、签名校验一定通过。
        signer = signer_obs or obs_client
        resp = signer.createSignedUrl(
            "GET", bucket, key, expires=expires_in,
        )
        presigned_url = resp.signedUrl
    except Exception as e:
        logger.error(
            "sign URL raised: %s %s", type(e).__name__, str(e), exc_info=True,
        )
        return api_response(
            500,
            ErrorResponse(
                error="Failed to generate download URL. (%s: %s)"
                % (type(e).__name__, str(e)[:150])
            ),
        )

    return api_response(200, TokenExchangeResponse(presigned_url=presigned_url))


def handler(event, context):
    """函数入口。event 由接入层触发器注入，含 httpMethod / path / body。"""
    try:
        setup_clients(context)
        _ensure_table()
    except Exception as e:
        logger.error("initialization failed: %s %s",
                     type(e).__name__, str(e), exc_info=True)
        return api_response(
            500,
            ErrorResponse(error="Storage initialization failed. (%s)" % str(e)[:200]),
        )
    logger.info("Invoked: %s %s", event.get("httpMethod"), event.get("path"))

    handler_name, error_response = route(event)
    if error_response:
        return error_response
    if handler_name == "generate_token":
        return generate_token(event, context)
    return exchange_token(event, context)
