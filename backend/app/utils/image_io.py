"""Image upload validation and decoding."""

from __future__ import annotations

import io
from dataclasses import dataclass

import numpy as np
from fastapi import UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError

from app.config import Settings
from app.errors import InvalidImageError, PayloadTooLargeError, UnsupportedMediaTypeError

ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/jpg", "image/png", "image/webp"}
ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP", "MPO"}  # MPO = multi-picture JPEG from some phones

# Refuse decompression bombs well before PIL's own warning threshold.
Image.MAX_IMAGE_PIXELS = 60_000_000


@dataclass
class DecodedImage:
    rgb: np.ndarray  # H x W x 3, uint8, RGB, EXIF orientation applied

    @property
    def width(self) -> int:
        return int(self.rgb.shape[1])

    @property
    def height(self) -> int:
        return int(self.rgb.shape[0])


async def read_upload(upload: UploadFile, settings: Settings, field: str = "image") -> bytes:
    content_type = (upload.content_type or "").lower()
    # Some HTTP clients send application/octet-stream; the bytes are checked below anyway.
    if content_type and content_type not in ALLOWED_CONTENT_TYPES and content_type != "application/octet-stream":
        raise UnsupportedMediaTypeError(
            f"'{field}' must be a JPEG, PNG or WebP image (got {content_type})."
        )
    data = await upload.read(settings.max_upload_bytes + 1)
    if len(data) > settings.max_upload_bytes:
        raise PayloadTooLargeError(
            f"'{field}' exceeds the {settings.max_upload_bytes // (1024 * 1024)} MB upload limit."
        )
    if not data:
        raise InvalidImageError(f"'{field}' is empty.")
    return data


def decode_image(data: bytes, settings: Settings, field: str = "image") -> DecodedImage:
    try:
        with Image.open(io.BytesIO(data)) as img:
            if img.format not in ALLOWED_FORMATS:
                raise UnsupportedMediaTypeError(
                    f"'{field}' must be a JPEG, PNG or WebP image (got {img.format})."
                )
            img = ImageOps.exif_transpose(img)  # phone photos are often stored rotated
            img = img.convert("RGB")
            arr = np.asarray(img, dtype=np.uint8).copy()
    except UnsupportedMediaTypeError:
        raise
    except Image.DecompressionBombError as exc:
        raise InvalidImageError(f"'{field}' has too many pixels.") from exc
    except (UnidentifiedImageError, OSError, ValueError, ImportError) as exc:
        # ImportError: Ultralytics patches Image.open and may try optional HEIF support on failure.
        raise InvalidImageError(f"'{field}' could not be decoded as an image.") from exc

    h, w = arr.shape[:2]
    if min(h, w) < settings.min_image_side:
        raise InvalidImageError(
            f"'{field}' is too small ({w}x{h}); minimum side is {settings.min_image_side} px."
        )
    if max(h, w) > settings.max_image_side:
        raise InvalidImageError(
            f"'{field}' is too large ({w}x{h}); maximum side is {settings.max_image_side} px."
        )
    return DecodedImage(rgb=arr)


async def load_upload(upload: UploadFile, settings: Settings, field: str = "image") -> DecodedImage:
    return decode_image(await read_upload(upload, settings, field), settings, field)


def crop(rgb: np.ndarray, x1: float, y1: float, x2: float, y2: float, pad: float = 0.0) -> np.ndarray:
    """Crop with optional fractional padding, clamped to the image."""
    h, w = rgb.shape[:2]
    bw, bh = x2 - x1, y2 - y1
    x1 = int(max(0, np.floor(x1 - bw * pad)))
    y1 = int(max(0, np.floor(y1 - bh * pad)))
    x2 = int(min(w, np.ceil(x2 + bw * pad)))
    y2 = int(min(h, np.ceil(y2 + bh * pad)))
    if x2 <= x1 or y2 <= y1:
        raise InvalidImageError("The requested region lies outside the image.")
    return rgb[y1:y2, x1:x2]
