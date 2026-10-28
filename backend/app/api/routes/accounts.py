"""User accounts: registration, sign-in (password or Google), sessions,
profile and the user's personal items.

Sign-in returns a short-lived access token (send as ``Authorization: Bearer``)
and a refresh token that is exchanged for a new pair at ``/auth/refresh``.
"""

from __future__ import annotations

import logging
import re
import shutil
from collections.abc import Iterator
from datetime import timedelta
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, Request, Response, UploadFile
from fastapi.responses import FileResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import get_services
from app.db import Item, RefreshToken, User, utcnow
from app.errors import ApiError, ServiceUnavailableError
from app.schemas.accounts import (
    AuthResponse,
    GoogleLoginRequest,
    LoginRequest,
    ProfileFields,
    RefreshRequest,
    RegisterRequest,
    UserItem,
    UserProfile,
)
from app.schemas.common import ErrorResponse
from app.services.accounts.google import GoogleTokenError
from app.services.accounts.security import (
    TokenError,
    create_access_token,
    decode_access_token,
    hash_password,
    hash_refresh_token,
    needs_rehash,
    new_refresh_token,
    verify_password,
)
from app.services.registry import Services
from app.utils.image_io import decode_image, read_upload

logger = logging.getLogger("smartsight.accounts")

auth_router = APIRouter(prefix="/api/v1/auth", tags=["accounts"])
me_router = APIRouter(prefix="/api/v1/me", tags=["accounts"])

_bearer = HTTPBearer(auto_error=False, description="Access token from /api/v1/auth/login, /register or /google.")
_ITEM_ID = re.compile(r"[A-Za-z0-9_\-]{1,40}")
AUTH_ERRORS = {401: {"model": ErrorResponse}, 409: {"model": ErrorResponse},
               422: {"model": ErrorResponse}, 429: {"model": ErrorResponse}}


# ------------------------------------------------------------------ helpers
def get_db(request: Request) -> Iterator[Session]:
    yield from request.app.state.db.session()


def current_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
) -> User:
    if credentials is None:
        raise ApiError(401, "not_authenticated", "Please sign in to use your account.")
    try:
        user_id = decode_access_token(credentials.credentials, request.app.state.jwt_secret)
    except TokenError as exc:
        raise ApiError(401, exc.code, exc.message) from None
    user = db.get(User, user_id)
    if user is None:
        raise ApiError(401, "invalid_token", "This account no longer exists.")
    return user


def _issue_tokens(request: Request, db: Session, user: User, *, is_new_user: bool = False) -> AuthResponse:
    settings = request.app.state.settings
    access, expires_in = create_access_token(user.id, request.app.state.jwt_secret, settings)
    refresh, refresh_hash = new_refresh_token()
    db.add(RefreshToken(user_id=user.id, token_hash=refresh_hash,
                        expires_at=utcnow() + timedelta(days=settings.refresh_token_days)))
    db.commit()
    db.refresh(user)
    return AuthResponse(access_token=access, refresh_token=refresh, expires_in=expires_in,
                        user=UserProfile.from_user(user), is_new_user=is_new_user)


def _client_key(request: Request) -> str:
    return f"ip:{request.client.host if request.client else 'unknown'}"


def _ensure_unique(db: Session, *, email: str | None = None, nic: str | None = None,
                   exclude_user: str | None = None) -> None:
    if email:
        other = db.scalar(select(User).where(User.email == email))
        if other is not None and other.id != exclude_user:
            hint = " Use Continue with Google." if other.password_hash is None else " Sign in instead."
            raise ApiError(409, "email_in_use", f"An account with this email already exists.{hint}")
    if nic:
        other = db.scalar(select(User).where(User.nic == nic))
        if other is not None and other.id != exclude_user:
            raise ApiError(409, "nic_in_use", "An account with this NIC number already exists.")


def _apply_profile(user: User, p: ProfileFields) -> None:
    user.first_name = p.first_name
    user.last_name = p.last_name
    user.nic = p.nic
    user.birthday = p.birthday
    user.gender = p.gender.value if p.gender else None
    user.address_line1 = p.address_line1
    user.address_line2 = p.address_line2
    user.address_line3 = p.address_line3
    user.postal_code = p.postal_code
    user.mobile = p.mobile
    user.whatsapp = p.whatsapp
    user.whatsapp_same_as_mobile = p.whatsapp_same_as_mobile
    user.bmi = p.bmi
    user.eyesight = p.eyesight.value if p.eyesight else None


# --------------------------------------------------------------- sign in/up
@auth_router.post("/register", response_model=AuthResponse, status_code=201, responses=AUTH_ERRORS,
                  summary="Create an account with email and password")
def register(body: RegisterRequest, request: Request, db: Session = Depends(get_db)) -> AuthResponse:
    _ensure_unique(db, email=body.email, nic=body.nic)
    user = User(email=body.email, password_hash=hash_password(body.password))
    _apply_profile(user, body)
    db.add(user)
    try:
        db.flush()
    except IntegrityError:  # lost a race with a concurrent registration
        db.rollback()
        _ensure_unique(db, email=body.email, nic=body.nic)
        raise
    logger.info("Account created (password) id=%s", user.id)
    return _issue_tokens(request, db, user, is_new_user=True)


@auth_router.post("/login", response_model=AuthResponse, responses=AUTH_ERRORS,
                  summary="Sign in with email and password")
def login(body: LoginRequest, request: Request, db: Session = Depends(get_db)) -> AuthResponse:
    throttle = request.app.state.login_throttle
    email = body.email.lower()
    keys = (f"email:{email}", _client_key(request))
    wait = throttle.retry_after(*keys)
    if wait:
        minutes = max(1, round(wait / 60))
        raise ApiError(429, "too_many_attempts",
                       f"Too many failed sign-in attempts. Try again in about {minutes} minutes.",
                       {"retry_after_seconds": wait})

    user = db.scalar(select(User).where(User.email == email))
    if user is not None and user.password_hash is None:
        raise ApiError(401, "use_google_sign_in", "This account uses Google sign-in. Choose Continue with Google.")
    if not verify_password(body.password, user.password_hash if user else None):
        throttle.record_failure(*keys)
        raise ApiError(401, "invalid_credentials", "The email or password is incorrect.")

    throttle.reset(*keys)
    if needs_rehash(user.password_hash):
        user.password_hash = hash_password(body.password)
    return _issue_tokens(request, db, user)


@auth_router.post("/google", response_model=AuthResponse, responses={**AUTH_ERRORS, 503: {"model": ErrorResponse}},
                  summary="Sign in or sign up with a Google ID token")
def google_login(body: GoogleLoginRequest, request: Request, db: Session = Depends(get_db)) -> AuthResponse:
    """Verifies the Google ID token. New Google users get an account with
    ``profile_complete=false`` and should be asked for the remaining details."""
    verifier = request.app.state.google_verifier
    if not verifier.configured:
        raise ServiceUnavailableError("Google sign-in is not set up on this server.",
                                      {"reason": "SMARTSIGHT_GOOGLE_CLIENT_IDS is empty"})
    try:
        identity = verifier.verify(body.id_token)
    except GoogleTokenError as exc:
        logger.info("Rejected Google token: %s", exc)
        raise ApiError(401, "invalid_google_token", "Google sign-in could not be confirmed. Please try again.") from None
    if not identity.email_verified:
        raise ApiError(401, "google_email_unverified", "Your Google account email is not verified.")

    user = db.scalar(select(User).where(User.google_sub == identity.sub))
    if user is not None:
        return _issue_tokens(request, db, user)

    existing = db.scalar(select(User).where(User.email == identity.email))
    if existing is not None:
        # Password accounts are not linked automatically: their email address
        # was never verified, so it may not belong to the account's owner.
        raise ApiError(409, "email_in_use",
                       "An account with this email already exists. Sign in with your email and password.")

    user = User(email=identity.email, google_sub=identity.sub,
                first_name=identity.given_name[:60], last_name=identity.family_name[:60])
    db.add(user)
    db.flush()
    logger.info("Account created (google) id=%s", user.id)
    return _issue_tokens(request, db, user, is_new_user=True)


@auth_router.post("/refresh", response_model=AuthResponse, responses=AUTH_ERRORS,
                  summary="Exchange a refresh token for new tokens")
def refresh(body: RefreshRequest, request: Request, db: Session = Depends(get_db)) -> AuthResponse:
    row = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(body.refresh_token)))
    if row is None:
        raise ApiError(401, "invalid_refresh_token", "Your session has ended. Please sign in again.")
    now = utcnow()
    if row.revoked_at is not None:
        # A rotated token was used again: it may have been stolen. End every session.
        for t in db.scalars(select(RefreshToken).where(RefreshToken.user_id == row.user_id,
                                                       RefreshToken.revoked_at.is_(None))):
            t.revoked_at = now
        db.commit()
        logger.warning("Refresh token reuse detected; revoked all sessions for id=%s", row.user_id)
        raise ApiError(401, "invalid_refresh_token", "Your session has ended. Please sign in again.")
    if row.expires_at <= now:
        raise ApiError(401, "invalid_refresh_token", "Your session has expired. Please sign in again.")
    row.revoked_at = now
    return _issue_tokens(request, db, row.user)


@auth_router.post("/logout", status_code=204, summary="End this session")
def logout(body: RefreshRequest, db: Session = Depends(get_db)) -> Response:
    row = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(body.refresh_token)))
    if row is not None and row.revoked_at is None:
        row.revoked_at = utcnow()
        db.commit()
    return Response(status_code=204)


# ------------------------------------------------------------------ profile
@me_router.get("", response_model=UserProfile, responses={401: {"model": ErrorResponse}},
               summary="The signed-in user's profile")
def get_me(user: User = Depends(current_user)) -> UserProfile:
    return UserProfile.from_user(user)


@me_router.put("", response_model=UserProfile, responses=AUTH_ERRORS,
               summary="Update the profile (also completes a new Google account)")
def update_me(body: ProfileFields, user: User = Depends(current_user), db: Session = Depends(get_db)) -> UserProfile:
    _ensure_unique(db, nic=body.nic, exclude_user=user.id)
    _apply_profile(user, body)
    db.commit()
    db.refresh(user)
    return UserProfile.from_user(user)


@me_router.delete("", status_code=204, responses={401: {"model": ErrorResponse}},
                  summary="Delete the account, its sessions and its items")
def delete_me(request: Request, user: User = Depends(current_user), db: Session = Depends(get_db)) -> Response:
    folder = _user_dir(request, user.id)
    db.delete(user)
    db.commit()
    shutil.rmtree(folder, ignore_errors=True)
    logger.info("Account deleted id=%s", user.id)
    return Response(status_code=204)


# -------------------------------------------------------------------- items
def _user_dir(request: Request, user_id: str) -> Path:
    return request.app.state.settings.data_dir / "items" / user_id


def _item_or_404(db: Session, user: User, item_id: str) -> Item:
    item = db.scalar(select(Item).where(Item.user_id == user.id, Item.item_id == item_id))
    if item is None:
        raise ApiError(404, "not_found", "That item does not exist.")
    return item


def _to_schema(item: Item) -> UserItem:
    return UserItem(id=item.item_id, name=item.name, label=item.label,
                    photo_count=item.photo_count, created_at=item.created_at)


@me_router.get("/items", response_model=list[UserItem], responses={401: {"model": ErrorResponse}},
               summary="The user's registered personal items")
def list_items(user: User = Depends(current_user)) -> list[UserItem]:
    return [_to_schema(i) for i in user.items]


@me_router.post("/items", response_model=UserItem, status_code=201,
                responses={**AUTH_ERRORS, 413: {"model": ErrorResponse}, 415: {"model": ErrorResponse}},
                summary="Save a personal item and its reference photos")
async def create_item(
    request: Request,
    response: Response,
    id: str = Form(..., max_length=40, description="Item id chosen by the app."),
    name: str = Form(..., min_length=1, max_length=80),
    label: str = Form(..., max_length=64, description="Detector class, e.g. 'cell phone'."),
    photos: list[UploadFile] = File(..., description="1-5 reference photos."),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
    services: Services = Depends(get_services),
) -> UserItem:
    """Saving the same id twice returns the existing item, so an app can
    safely retry an upload that timed out."""
    s = services.settings
    if not _ITEM_ID.fullmatch(id):
        raise ApiError(422, "validation_error", "The item id may only contain letters, digits, '-' and '_'.")
    existing = db.scalar(select(Item).where(Item.user_id == user.id, Item.item_id == id))
    if existing is not None:
        response.status_code = 200
        return _to_schema(existing)
    if services.detector.is_ready() and label not in services.detector.classes:
        raise ApiError(422, "unsupported_class", f"'{label}' is not a class the detector can recognise.")
    if not 1 <= len(photos) <= s.item_max_references:
        raise ApiError(422, "validation_error", f"Provide between 1 and {s.item_max_references} photos.")
    if len(user.items) >= s.max_items_per_user:
        raise ApiError(422, "too_many_items", f"You can register up to {s.max_items_per_user} items.")

    data = []
    for i, p in enumerate(photos):
        raw = await read_upload(p, s, f"photos[{i}]")
        decode_image(raw, s, f"photos[{i}]")  # reject anything that is not a real image
        data.append(raw)

    folder = _user_dir(request, user.id) / id
    folder.mkdir(parents=True, exist_ok=True)
    for i, raw in enumerate(data):
        (folder / f"{i}.jpg").write_bytes(raw)
    item = Item(user_id=user.id, item_id=id, name=name.strip(), label=label, photo_count=len(data))
    db.add(item)
    db.commit()
    return _to_schema(item)


@me_router.delete("/items/{item_id}", status_code=204, responses={401: {"model": ErrorResponse},
                                                                  404: {"model": ErrorResponse}},
                  summary="Delete a personal item")
def delete_item(item_id: str, request: Request, user: User = Depends(current_user),
                db: Session = Depends(get_db)) -> Response:
    item = _item_or_404(db, user, item_id)
    db.delete(item)
    db.commit()
    shutil.rmtree(_user_dir(request, user.id) / item.item_id, ignore_errors=True)
    return Response(status_code=204)


@me_router.get("/items/{item_id}/photos/{index}", response_class=FileResponse,
               responses={200: {"content": {"image/jpeg": {}}}, 401: {"model": ErrorResponse},
                          404: {"model": ErrorResponse}},
               summary="Download one reference photo of an item")
def item_photo(item_id: str, index: int, request: Request, user: User = Depends(current_user),
               db: Session = Depends(get_db)) -> FileResponse:
    item = _item_or_404(db, user, item_id)
    path = _user_dir(request, user.id) / item.item_id / f"{index}.jpg"
    if not 0 <= index < item.photo_count or not path.is_file():
        raise ApiError(404, "not_found", "That photo does not exist.")
    return FileResponse(path, media_type="image/jpeg")
