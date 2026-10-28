"""Database models and session handling for user accounts.

SQLite by default (one file under ``data_dir``); any SQLAlchemy URL can be
configured with ``SMARTSIGHT_DATABASE_URL``. Tables are created on start-up.

All timestamps are stored as naive UTC.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import date, datetime, timezone
from pathlib import Path

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    create_engine,
    event,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, relationship, sessionmaker


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def new_id() -> str:
    return uuid.uuid4().hex


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    email: Mapped[str] = mapped_column(String(254), unique=True, index=True)
    # None for accounts created with Google that never set a password.
    password_hash: Mapped[str | None] = mapped_column(String(255))
    google_sub: Mapped[str | None] = mapped_column(String(64), unique=True, index=True)

    first_name: Mapped[str] = mapped_column(String(60), default="")
    last_name: Mapped[str] = mapped_column(String(60), default="")
    nic: Mapped[str | None] = mapped_column(String(12), unique=True, index=True)
    birthday: Mapped[date | None] = mapped_column(Date)
    gender: Mapped[str | None] = mapped_column(String(24))
    address_line1: Mapped[str | None] = mapped_column(String(120))
    address_line2: Mapped[str | None] = mapped_column(String(120))
    address_line3: Mapped[str | None] = mapped_column(String(120))
    postal_code: Mapped[str | None] = mapped_column(String(10))
    mobile: Mapped[str | None] = mapped_column(String(20))
    whatsapp: Mapped[str | None] = mapped_column(String(20))
    whatsapp_same_as_mobile: Mapped[bool] = mapped_column(Boolean, default=False)
    bmi: Mapped[float | None] = mapped_column(Float)
    eyesight: Mapped[str | None] = mapped_column(String(32))

    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)

    refresh_tokens: Mapped[list[RefreshToken]] = relationship(
        back_populates="user", cascade="all, delete-orphan", passive_deletes=True)
    items: Mapped[list[Item]] = relationship(
        back_populates="user", cascade="all, delete-orphan", passive_deletes=True, order_by="Item.created_at")

    @property
    def profile_complete(self) -> bool:
        required = (self.first_name, self.last_name, self.nic, self.birthday, self.gender,
                    self.address_line1, self.postal_code, self.mobile)
        return all(v not in (None, "") for v in required)


class RefreshToken(Base):
    """One row per issued refresh token. Only a SHA-256 hash is stored.

    Tokens rotate on every refresh. Presenting a token that was already
    rotated or revoked revokes every session of that user (reuse detection).
    """

    __tablename__ = "refresh_tokens"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime)

    user: Mapped[User] = relationship(back_populates="refresh_tokens")


class Item(Base):
    """A personal item registered by a user. Photos live under data_dir/items."""

    __tablename__ = "items"
    __table_args__ = (UniqueConstraint("user_id", "item_id"),)

    pk: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    # Chosen by the app so an item created offline keeps its id after syncing.
    item_id: Mapped[str] = mapped_column(String(40))
    name: Mapped[str] = mapped_column(String(80))
    label: Mapped[str] = mapped_column(String(64))
    photo_count: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    user: Mapped[User] = relationship(back_populates="items")


class Database:
    def __init__(self, url: str):
        if url.startswith("sqlite:///"):
            Path(url.removeprefix("sqlite:///")).parent.mkdir(parents=True, exist_ok=True)
        self.engine = create_engine(
            url, connect_args={"check_same_thread": False} if url.startswith("sqlite") else {})
        if url.startswith("sqlite"):
            event.listen(self.engine, "connect", _sqlite_pragmas)
        self._sessions = sessionmaker(self.engine, expire_on_commit=False)
        Base.metadata.create_all(self.engine)

    def session(self) -> Iterator[Session]:
        with self._sessions() as s:
            yield s

    def dispose(self) -> None:
        self.engine.dispose()


def _sqlite_pragmas(dbapi_conn, _record) -> None:
    cur = dbapi_conn.cursor()
    cur.execute("PRAGMA foreign_keys=ON")
    cur.execute("PRAGMA journal_mode=WAL")
    cur.close()
