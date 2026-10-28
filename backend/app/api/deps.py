from __future__ import annotations

from datetime import datetime, timezone

from fastapi import Request

from app.errors import ServiceUnavailableError
from app.schemas.common import BoundingBox, FrameInfo
from app.schemas.detection import Detection, DetectionResponse, ProcessingInfo
from app.services.interfaces import DetectorOutput
from app.services.registry import Services
from app.services.spatial import relative_position


def get_services(request: Request) -> Services:
    return request.app.state.services


def require_detector(services: Services) -> None:
    if not services.detector.is_ready():
        raise ServiceUnavailableError(
            "The object-detection model is not loaded.",
            {"reason": services.load_errors.get("detector")},
        )


def form_bool(value: str | None, default: bool, name: str) -> bool:
    """Parse a multipart boolean. FastAPI turns a *missing* bool form field into
    False, which would silently ignore our defaults, so booleans arrive as text."""
    if value is None or value == "":
        return default
    v = value.strip().lower()
    if v in {"true", "1", "yes", "on"}:
        return True
    if v in {"false", "0", "no", "off"}:
        return False
    from app.errors import ApiError

    raise ApiError(422, "validation_error", f"'{name}' must be true or false.")


def validate_fov(value: float | None) -> float | None:
    if value is None:
        return None
    if not 10 < value < 170:
        from app.errors import ApiError

        raise ApiError(422, "validation_error", "camera_fov_degrees must be between 10 and 170.")
    return value


def to_detections(
    out: DetectorOutput,
    frame: FrameInfo,
    services: Services,
    *,
    include_position: bool = True,
    include_distance: bool = True,
    fov: float | None = None,
) -> list[Detection]:
    fov = fov or services.settings.camera_fov_degrees
    dets: list[Detection] = []
    for i, d in enumerate(out.detections):
        bbox = BoundingBox(x1=d.x1, y1=d.y1, x2=d.x2, y2=d.y2)
        norm = BoundingBox(
            x1=round(d.x1 / frame.width, 5), y1=round(d.y1 / frame.height, 5),
            x2=round(d.x2 / frame.width, 5), y2=round(d.y2 / frame.height, 5),
        )
        dets.append(Detection(
            id=i,
            label=d.label,
            class_id=d.class_id,
            confidence=round(d.confidence, 4),
            bbox=BoundingBox(x1=round(d.x1, 1), y1=round(d.y1, 1), x2=round(d.x2, 1), y2=round(d.y2, 1)),
            bbox_normalised=norm,
            position=relative_position(bbox, frame, fov) if include_position else None,
            distance=(services.distance.estimate(d.label, bbox, frame, fov)
                      if include_distance and services.distance else None),
        ))
    return dets


def detection_response(
    out: DetectorOutput,
    frame: FrameInfo,
    services: Services,
    confidence: float,
    total_ms: float,
    **kwargs,
) -> DetectionResponse:
    t = out.timings_ms
    notes = [
        "Only the detector's 80 COCO classes can be recognised; see GET /api/v1/detection/classes.",
    ]
    if services.distance:
        notes.append("Distances are approximate monocular estimates based on typical object sizes.")
    return DetectionResponse(
        frame=frame,
        timestamp=datetime.now(timezone.utc),
        detections=to_detections(out, frame, services, **kwargs),
        model=services.detector.info,
        processing=ProcessingInfo(
            preprocess_ms=round(t["preprocess"], 1) if "preprocess" in t else None,
            inference_ms=round(t["inference"], 1) if "inference" in t else None,
            postprocess_ms=round(t["postprocess"], 1) if "postprocess" in t else None,
            total_ms=round(total_ms, 1),
            confidence_threshold=confidence,
            image_size=services.settings.detection_image_size,
            device=services.settings.inference_device,
        ),
        notes=notes,
    )
