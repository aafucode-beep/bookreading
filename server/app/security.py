from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import time
from dataclasses import dataclass

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import Settings, get_settings
from .database import get_session
from .models import User


bearer = HTTPBearer(auto_error=False)


def hash_secret(secret: str, *, iterations: int = 600_000) -> str:
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", secret.encode(), salt, iterations)
    return f"pbkdf2_sha256${iterations}${base64.urlsafe_b64encode(salt).decode()}${base64.urlsafe_b64encode(digest).decode()}"


def verify_secret(secret: str, encoded: str) -> bool:
    try:
        algorithm, iterations, salt, expected = encoded.split("$", 3)
        if algorithm != "pbkdf2_sha256":
            return False
        actual = hashlib.pbkdf2_hmac(
            "sha256", secret.encode(), base64.urlsafe_b64decode(salt), int(iterations)
        )
        return hmac.compare_digest(actual, base64.urlsafe_b64decode(expected))
    except (ValueError, TypeError):
        return False


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def _unb64(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def create_token(user_id: int, token_type: str, ttl_seconds: int, settings: Settings) -> str:
    now = int(time.time())
    header = _b64(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = _b64(
        json.dumps(
            {"sub": str(user_id), "type": token_type, "iat": now, "exp": now + ttl_seconds},
            separators=(",", ":"),
        ).encode()
    )
    signature = _b64(hmac.new(settings.secret_key.encode(), f"{header}.{payload}".encode(), hashlib.sha256).digest())
    return f"{header}.{payload}.{signature}"


def decode_token(token: str, settings: Settings, expected_type: str | None = None) -> dict:
    try:
        header, payload, signature = token.split(".")
        expected = _b64(
            hmac.new(settings.secret_key.encode(), f"{header}.{payload}".encode(), hashlib.sha256).digest()
        )
        if not hmac.compare_digest(signature, expected):
            raise ValueError("bad signature")
        data = json.loads(_unb64(payload))
        if int(data["exp"]) <= int(time.time()):
            raise ValueError("expired")
        if expected_type and data.get("type") != expected_type:
            raise ValueError("wrong token type")
        return data
    except (ValueError, KeyError, json.JSONDecodeError) as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="登录已失效") from exc


def authenticate(session: Session, username: str, password: str) -> User | None:
    user = session.scalar(select(User).where(User.username == username, User.is_active.is_(True)))
    if not user or not verify_secret(password, user.password_hash):
        return None
    return user


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    session: Session = Depends(get_session),
    settings: Settings = Depends(get_settings),
) -> User:
    if credentials is None:
        raise HTTPException(status_code=401, detail="请先登录")
    payload = decode_token(credentials.credentials, settings, "access")
    user = session.get(User, int(payload["sub"]))
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="账号不可用")
    return user


def require_parent_pin(
    request: Request,
    user: User = Depends(get_current_user),
) -> User:
    pin = request.headers.get("x-parent-pin", "")
    if not verify_secret(pin, user.pin_hash):
        raise HTTPException(status_code=403, detail="家长 PIN 不正确")
    return user


@dataclass(slots=True)
class TokenPair:
    access_token: str
    refresh_token: str
    expires_in: int


def issue_token_pair(user_id: int, settings: Settings) -> TokenPair:
    access_seconds = settings.access_token_minutes * 60
    return TokenPair(
        access_token=create_token(user_id, "access", access_seconds, settings),
        refresh_token=create_token(user_id, "refresh", settings.refresh_token_days * 86400, settings),
        expires_in=access_seconds,
    )

