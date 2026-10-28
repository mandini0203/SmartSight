from __future__ import annotations

import time

from fastapi import APIRouter, Depends, File, Form, UploadFile

from app.api.deps import detection_response, form_bool, get_services, require_detector, validate_fov
from app.errors import ApiError
from app.schemas.common import ErrorResponse, FrameInfo
from app.schemas.detection import DetectionResponse, SupportedClassesResponse
from app.services.registry import Services
from app.utils.image_io import load_upload

router = APIRouter(prefix="/api/v1/detection", tags=["detection"])

ERRORS = {
    413: {"model": ErrorResponse}, 415: {"model": ErrorResponse}, 422: {"model": ErrorResponse},
    503: {"model": ErrorResponse}, 504: {"model": ErrorResponse},
}


@router.get("/classes", response_model=SupportedClassesResponse, summary="Classes the detector can recognise")
def classes(services: Services = Depends(get_services)) -> SupportedClassesResponse:
    require_detector(services)
    return SupportedClassesResponse(
        model=services.detector.info,
        classes=services.detector.classes,
        notes=[
            "Objects outside this list (for example keys, wallets, glasses, doors) are not "
            "recognised by this detector.",
            "Doors and exit signs are handled separately by POST /api/v1/signs/detect.",
        ],
    )


@router.post("", response_model=DetectionResponse, responses=ERRORS, summary="Run YOLOv8 object detection")
async def detect(
    image: UploadFile = File(..., description="JPEG, PNG or WebP image."),
    confidence: float | None = Form(None, ge=0.01, le=0.99, description="Override confidence threshold."),
    classes: str | None = Form(None, max_length=1000, description="Comma-separated class filter, e.g. 'person,chair'."),
    frame_id: str | None = Form(None, max_length=64),
    include_position: str | None = Form(None, description="true/false (default true)."),
    include_distance: str | None = Form(None, description="true/false (default true)."),
    camera_fov_degrees: float | None = Form(None, description="Camera FOV across the long image side."),
    services: Services = Depends(get_services),
) -> DetectionResponse:
    """Runs real inference with the configured pretrained YOLOv8 checkpoint."""
    start = time.perf_counter()
    require_detector(services)
    fov = validate_fov(camera_fov_degrees)
    class_filter = None
    if classes:
        class_filter = [c.strip() for c in classes.split(",") if c.strip()]
        unknown = [c for c in class_filter if c not in services.detector.classes]
        if unknown:
            raise ApiError(422, "unsupported_class", "Some requested classes are not supported by the detector.",
                           {"unsupported": unknown})
    img = await load_upload(image, services.settings)
    conf = confidence if confidence is not None else services.settings.detection_confidence
    out = await services.gate.run(services.detector.detect, img.rgb, confidence=conf, classes=class_filter)
    frame = FrameInfo(width=img.width, height=img.height, frame_id=frame_id)
    return detection_response(
        out, frame, services, conf, (time.perf_counter() - start) * 1000,
        include_position=form_bool(include_position, True, "include_position"),
        include_distance=form_bool(include_distance, True, "include_distance"), fov=fov,
    )
