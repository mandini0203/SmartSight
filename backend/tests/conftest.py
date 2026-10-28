"""Shared fixtures.

The API tests use the *real* services: actual YOLOv8 / YOLO-World inference and
the real matcher. Model loading happens once per test session.
"""

from __future__ import annotations

import dataclasses
import io
from pathlib import Path

import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw

from app.config import Settings
from app.main import create_app
from app.services.registry import build_services

try:
    from ultralytics.utils import ASSETS
except Exception:  # pragma: no cover
    ASSETS = None


@pytest.fixture(scope="session")
def settings(tmp_path_factory) -> Settings:
    return Settings(environment="test", warmup_on_startup=False, log_level="WARNING",
                    data_dir=tmp_path_factory.mktemp("data"), database_url="")


@pytest.fixture(scope="session")
def services(settings):
    return build_services(settings)


@pytest.fixture(scope="session")
def client(settings, services):
    with TestClient(create_app(settings, services)) as c:
        yield c


@pytest.fixture
def make_client(services):
    """Client with modified settings sharing the already-loaded models."""
    clients = []

    def _make(**overrides):
        s = services.settings.model_copy(update=overrides)
        c = TestClient(create_app(s, dataclasses.replace(services, settings=s)))
        c.__enter__()
        clients.append(c)
        return c

    yield _make
    for c in clients:
        c.__exit__(None, None, None)


def _asset(name: str) -> Path:
    if ASSETS is None or not (Path(ASSETS) / name).is_file():
        pytest.skip(f"Ultralytics sample image {name} not available")
    return Path(ASSETS) / name


@pytest.fixture(scope="session")
def bus_jpg() -> bytes:
    return _asset("bus.jpg").read_bytes()


@pytest.fixture(scope="session")
def zidane_jpg() -> bytes:
    return _asset("zidane.jpg").read_bytes()


def encode(img: Image.Image, fmt: str = "JPEG") -> bytes:
    buf = io.BytesIO()
    img.save(buf, format=fmt, quality=95) if fmt == "JPEG" else img.save(buf, format=fmt)
    return buf.getvalue()


@pytest.fixture
def solid_image():
    def _make(rgb, size=(320, 240), fmt="PNG") -> bytes:
        return encode(Image.new("RGB", size, rgb), fmt)
    return _make


@pytest.fixture(scope="session")
def exit_sign_png() -> bytes:
    """Synthetic grey wall with an illuminated green exit-sign-like panel."""
    img = Image.new("RGB", (640, 480), (150, 150, 145))
    d = ImageDraw.Draw(img)
    d.rectangle([380, 60, 560, 130], fill=(0, 170, 70))
    d.rectangle([410, 80, 530, 110], fill=(245, 245, 245))
    arr = np.asarray(img).copy()
    return encode(Image.fromarray(arr), "PNG")
