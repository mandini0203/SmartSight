"""Password hashing, access tokens and refresh tokens.

* Passwords: Argon2id (argon2-cffi defaults), re-hashed on login when the
  parameters change.
* Access tokens: short-lived HS256 JWTs carrying only the user id.
* Refresh tokens: random 64-byte strings; the database stores SHA-256 hashes.
"""

from __future__ import annotations

import hashlib
import logging
import secrets
from datetime import datetime, timedelta, timezone

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError

from app.config import Settings

logger = logging.getLogger("smartsight.accounts")

ISSUER = "smartsight"
_hasher = PasswordHasher()
# Verified against when the email is unknown, so response time does not
# reveal whether an account exists.
_DUMMY_HASH = _hasher.hash("smartsight-timing-equaliser")


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str | None) -> bool:
    try:
        return _hasher.verify(password_hash or _DUMMY_HASH, password) and password_hash is not None
    except (VerificationError, InvalidHashError):
        return False


def needs_rehash(password_hash: str) -> bool:
    return _hasher.check_needs_rehash(password_hash)


def resolve_jwt_secret(settings: Settings) -> str:
    if settings.jwt_secret:
        if len(settings.jwt_secret) < 32:
            raise RuntimeError("SMARTSIGHT_JWT_SECRET must be at least 32 characters.")
        return settings.jwt_secret
    if settings.environment == "production":
        raise RuntimeError("SMARTSIGHT_JWT_SECRET must be set when SMARTSIGHT_ENVIRONMENT=production.")
    path = settings.data_dir / "jwt_secret"
    if path.is_file():
        return path.read_text(encoding="utf-8").strip()
    settings.data_dir.mkdir(parents=True, exist_ok=True)
    secret = secrets.token_urlsafe(48)
    path.write_text(secret, encoding="utf-8")
    logger.warning("Generated a development JWT secret in %s. Set SMARTSIGHT_JWT_SECRET in production.", path)
    return secret


def create_access_token(user_id: str, secret: str, settings: Settings) -> tuple[str, int]:
    now = datetime.now(timezone.utc)
    lifetime = timedelta(minutes=settings.access_token_minutes)
    token = jwt.encode(
        {"sub": user_id, "iss": ISSUER, "typ": "access", "iat": now, "exp": now + lifetime},
        secret,
        algorithm="HS256",
    )
    return token, int(lifetime.total_seconds())


class TokenError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def decode_access_token(token: str, secret: str) -> str:
    """Returns the user id, or raises TokenError."""
    try:
        claims = jwt.decode(token, secret, algorithms=["HS256"], issuer=ISSUER,
                            options={"require": ["sub", "exp", "iat", "iss"]})
    except jwt.ExpiredSignatureError:
        raise TokenError("token_expired", "Your session has expired. Please sign in again.") from None
    except jwt.InvalidTokenError:
        raise TokenError("invalid_token", "The sign-in token is not valid. Please sign in again.") from None
    if claims.get("typ") != "access":
        raise TokenError("invalid_token", "The sign-in token is not valid. Please sign in again.")
    return str(claims["sub"])


def new_refresh_token() -> tuple[str, str]:
    """Returns (token for the client, hash for the database)."""
    token = secrets.token_urlsafe(64)
    return token, hash_refresh_token(token)


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()
