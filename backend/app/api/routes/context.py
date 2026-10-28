from __future__ import annotations

import time

from fastapi import APIRouter, Depends, File, Form, UploadFile
from pydantic import BaseModel

from app.api.deps import detection_response, get_services, require_detector, validate_fov
from app.api.routes.signs import run_sign_detection
from app.schemas.common import ErrorResponse, FrameInfo
from app.schemas.context import ContextRequest, ContextResponse, InputDetection, TaskType
from app.schemas.detection import DetectionResponse
from app.schemas.signs import SignsResponse
from app.services.registry import Services
from app.utils.image_io import load_upload

router = APIRouter(prefix="/api/v1", tags=["context"])


@router.post(
    "/context/analyse",
    response_model=ContextResponse,
    responses={422: {"model": ErrorResponse}},
    summary="Rule-based context analysis of supplied detections",
)
def analyse(request: ContextRequest, services: Services = Depends(get_services)) -> ContextResponse:
    """Applies the rule-based context reasoner to detections (normally from /detection).

    Each relationship, seat assessment and guidance message lists its evidence.
    This is a deterministic baseline, not a trained model.
    """
    return services.context.analyse(request)


class ScanResponse(BaseModel):
    detection: DetectionResponse
    signs: SignsResponse | None
    context: ContextResponse


@router.post(
    "/scan",
    response_model=ScanResponse,
    responses={413: {"model": ErrorResponse}, 415: {"model": ErrorResponse}, 422: {"model": ErrorResponse},
               503: {"model": ErrorResponse}, 504: {"model": ErrorResponse}},
    summary="Detection + context analysis in one request (used by the app)",
)
async def scan(
    image: UploadFile = File(...),
    task: TaskType = Form(TaskType.DESCRIBE_SURROUNDINGS),
    target_label: str | None = Form(None, max_length=64),
    frame_id: str | None = Form(None, max_length=64),
    camera_fov_degrees: float | None = Form(None),
    services: Services = Depends(get_services),
) -> ScanResponse:
    """Saves a round trip on mobile networks. For ``find_exit`` the door/exit-sign
    detector also runs and its candidates are passed to the context reasoner."""
    start = time.perf_counter()
    require_detector(services)
    fov = validate_fov(camera_fov_degrees)
    img = await load_upload(image, services.settings)
    conf = services.settings.detection_confidence
    out = await services.gate.run(services.detector.detect, img.rgb, confidence=conf)
    frame = FrameInfo(width=img.width, height=img.height, frame_id=frame_id)
    det = detection_response(out, frame, services, conf, (time.perf_counter() - start) * 1000, fov=fov)

    inputs = [InputDetection(id=d.id, label=d.label, confidence=d.confidence, bbox=d.bbox) for d in det.detections]
    signs = None
    if task == TaskType.FIND_EXIT:
        signs = await run_sign_detection(img, frame, services, fov)
        next_id = len(inputs)
        for i, c in enumerate(signs.candidates):
            inputs.append(InputDetection(id=next_id + i, label=c.kind.value.replace("_", " "),
                                         confidence=c.confidence, bbox=c.bbox))
    ctx = services.context.analyse(
        ContextRequest(frame=frame, detections=inputs, task=task, target_label=target_label), fov,
    )
    return ScanResponse(detection=det, signs=signs, context=ctx)
