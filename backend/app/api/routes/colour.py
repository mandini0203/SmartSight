from __future__ import annotations

from fastapi import APIRouter, Depends, File, Form, UploadFile

from app.api.deps import form_bool, get_services
from app.errors import ApiError
from app.schemas.colour import ColourResponse
from app.schemas.common import BoundingBox, ErrorResponse, FrameInfo
from app.services.registry import Services
from app.utils.image_io import load_upload

router = APIRouter(prefix="/api/v1/colour", tags=["colour"])

CENTRE_FRACTION = 0.3   # default region: central 30 % x 30 % of the frame
POINT_FRACTION = 0.15   # region around a tapped point when no object contains it


def _clamp_box(x1, y1, x2, y2, w, h) -> BoundingBox:
    x1, y1 = max(0.0, min(x1, w - 1)), max(0.0, min(y1, h - 1))
    x2, y2 = max(x1 + 1, min(x2, w)), max(y1 + 1, min(y2, h))
    return BoundingBox(x1=x1, y1=y1, x2=x2, y2=y2)


@router.post(
    "/identify",
    response_model=ColourResponse,
    responses={413: {"model": ErrorResponse}, 415: {"model": ErrorResponse}, 422: {"model": ErrorResponse}},
    summary="Identify the dominant colour of a region or selected object",
)
async def identify(
    image: UploadFile = File(...),
    x1: float | None = Form(None, ge=0), y1: float | None = Form(None, ge=0),
    x2: float | None = Form(None, ge=0), y2: float | None = Form(None, ge=0),
    normalised: str | None = Form(None, description="true: box/point values are 0..1 fractions of the image size."),
    point_x: float | None = Form(None, ge=0, description="Tapped point; selects the smallest object containing it."),
    point_y: float | None = Form(None, ge=0),
    frame_id: str | None = Form(None, max_length=64),
    services: Services = Depends(get_services),
) -> ColourResponse:
    """Region priority: explicit box > tapped point (object under it, else a small square) > image centre."""
    img = await load_upload(image, services.settings)
    w, h = img.width, img.height
    sx, sy = (w, h) if form_bool(normalised, False, "normalised") else (1.0, 1.0)
    frame = FrameInfo(width=w, height=h, frame_id=frame_id)

    box_values = [x1, y1, x2, y2]
    if any(v is not None for v in box_values):
        if any(v is None for v in box_values):
            raise ApiError(422, "validation_error", "Provide all of x1, y1, x2, y2 or none of them.")
        bx1, by1, bx2, by2 = x1 * sx, y1 * sy, x2 * sx, y2 * sy
        if bx2 <= bx1 or by2 <= by1:
            raise ApiError(422, "validation_error", "The region must satisfy x2 > x1 and y2 > y1.")
        region, source = _clamp_box(bx1, by1, bx2, by2, w, h), "bbox"
    elif point_x is not None and point_y is not None:
        px, py = point_x * sx, point_y * sy
        if px > w or py > h:
            raise ApiError(422, "validation_error", "The point lies outside the image.")
        region, source = None, "point"
        if services.detector.is_ready():
            out = await services.gate.run(services.detector.detect, img.rgb)
            hits = [d for d in out.detections if d.x1 <= px <= d.x2 and d.y1 <= py <= d.y2]
            if hits:
                d = min(hits, key=lambda d: (d.x2 - d.x1) * (d.y2 - d.y1))
                region, source = _clamp_box(d.x1, d.y1, d.x2, d.y2, w, h), f"detection:{d.label}"
        if region is None:
            half = POINT_FRACTION * min(w, h) / 2
            region = _clamp_box(px - half, py - half, px + half, py + half, w, h)
    else:
        cw, ch = w * CENTRE_FRACTION / 2, h * CENTRE_FRACTION / 2
        region, source = _clamp_box(w / 2 - cw, h / 2 - ch, w / 2 + cw, h / 2 + ch, w, h), "centre"

    return services.colour.identify(img.rgb, region, source, frame)
