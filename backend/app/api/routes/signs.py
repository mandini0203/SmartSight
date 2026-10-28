from __future__ import annotations

import time
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, Form, UploadFile

from app.api.deps import get_services, validate_fov
from app.errors import ServiceUnavailableError
from app.schemas.common import BoundingBox, ErrorResponse, FrameInfo
from app.schemas.signs import SignCandidate, SignKind, SignsResponse
from app.services.distance import spoken_distance
from app.services.registry import Services
from app.services.spatial import relative_position
from app.utils.image_io import DecodedImage, load_upload

router = APIRouter(prefix="/api/v1/signs", tags=["doors and signs"])


async def run_sign_detection(img: DecodedImage, frame: FrameInfo, services: Services,
                             fov: float | None) -> SignsResponse:
    if not services.door_sign.is_ready():
        raise ServiceUnavailableError("The door and sign detector is not available.")
    start = time.perf_counter()
    raw = await services.gate.run(services.door_sign.detect, img.rgb)
    fov = fov or services.settings.camera_fov_degrees
    candidates: list[SignCandidate] = []
    for r in raw[:15]:
        bbox = BoundingBox(x1=round(r.box[0], 1), y1=round(r.box[1], 1), x2=round(r.box[2], 1), y2=round(r.box[3], 1))
        label = "exit sign" if r.kind == "exit_sign" else "door"
        candidates.append(SignCandidate(
            kind=SignKind(r.kind), confidence=r.confidence, detector_confidence=r.detector_confidence,
            bbox=bbox, position=relative_position(bbox, frame, fov),
            distance=services.distance.estimate(label, bbox, frame, fov) if services.distance else None,
            evidence=r.evidence, sign_colour=r.sign_colour,
        ))
    notes = ["Candidates must be confirmed by the user; signs and doors can be missed or confused."]
    if "door" not in services.door_sign.supported_kinds:
        notes.append("Door detection is unavailable with the current fallback detector.")
    if candidates:
        best = candidates[0]
        noun = "An exit sign" if best.kind == SignKind.EXIT_SIGN else "A door"
        where = best.position.description.split(",")[0]
        msg = f"{noun} may be {where}, at {best.position.clock_label}"
        if best.distance:
            msg += f", {spoken_distance(best.distance)}"
        msg += "."
        if best.confidence < 0.35:
            msg += " Low confidence."
    else:
        msg = "No exit signs or doors detected in this view."
    return SignsResponse(
        frame=frame, timestamp=datetime.now(timezone.utc), candidates=candidates, message=msg,
        detector=services.door_sign.info, processing_ms=round((time.perf_counter() - start) * 1000, 1),
        notes=notes,
    )


@router.post(
    "/detect",
    response_model=SignsResponse,
    responses={413: {"model": ErrorResponse}, 415: {"model": ErrorResponse}, 422: {"model": ErrorResponse},
               503: {"model": ErrorResponse}, 504: {"model": ErrorResponse}},
    summary="Find exit-sign and door candidates",
)
async def detect_signs(
    image: UploadFile = File(...),
    frame_id: str | None = Form(None, max_length=64),
    camera_fov_degrees: float | None = Form(None),
    services: Services = Depends(get_services),
) -> SignsResponse:
    fov = validate_fov(camera_fov_degrees)
    img = await load_upload(image, services.settings)
    frame = FrameInfo(width=img.width, height=img.height, frame_id=frame_id)
    return await run_sign_detection(img, frame, services, fov)
