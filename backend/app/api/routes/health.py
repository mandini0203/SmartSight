from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app import __version__
from app.api.deps import get_services
from app.schemas.common import ComponentInfo
from app.schemas.detection import ModelInfo
from app.services.registry import Services

router = APIRouter(tags=["health"])


class HealthResponse(BaseModel):
    status: str
    version: str
    time: datetime


class ComponentStatus(BaseModel):
    ready: bool
    component: ComponentInfo
    note: str | None = None


class StatusResponse(BaseModel):
    status: str  # "ok" | "degraded" | "unavailable"
    version: str
    detector: ComponentStatus
    detector_model: ModelInfo | None
    door_sign: ComponentStatus
    item_matcher: ComponentStatus
    colour: ComponentStatus
    context: ComponentStatus
    intent: ComponentStatus
    distance: ComponentStatus | None
    limits: dict[str, float]
    load_errors: dict[str, str]


@router.get("/health", response_model=HealthResponse, summary="Liveness check")
def health() -> HealthResponse:
    """Returns 200 whenever the API process is running. Use /api/v1/status for model readiness."""
    return HealthResponse(status="ok", version=__version__, time=datetime.now(timezone.utc))


@router.get("/api/v1/status", response_model=StatusResponse, summary="Service and model readiness")
def status(services: Services = Depends(get_services)) -> StatusResponse:
    det_ready = services.detector.is_ready()
    overall = "ok" if det_ready and not services.load_errors else ("degraded" if det_ready else "unavailable")
    s = services.settings
    return StatusResponse(
        status=overall,
        version=__version__,
        detector=ComponentStatus(ready=det_ready, component=services.detector.info,
                                 note=services.load_errors.get("detector")),
        detector_model=services.detector.info if det_ready else None,
        door_sign=ComponentStatus(ready=services.door_sign.is_ready(), component=services.door_sign.info,
                                  note=services.load_errors.get("door_sign")),
        item_matcher=ComponentStatus(ready=services.matcher.is_ready(), component=services.matcher.info,
                                     note=services.load_errors.get("item_matcher")),
        colour=ComponentStatus(ready=True, component=services.colour.info),
        context=ComponentStatus(ready=True, component=services.context.info),
        intent=ComponentStatus(ready=True, component=services.intent.info),
        distance=ComponentStatus(ready=True, component=services.distance.info) if services.distance else None,
        limits={
            "max_upload_bytes": s.max_upload_bytes,
            "max_image_side": s.max_image_side,
            "inference_timeout_seconds": s.inference_timeout_seconds,
            "detection_confidence": s.detection_confidence,
        },
        load_errors=services.load_errors,
    )
