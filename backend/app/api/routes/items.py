from __future__ import annotations

import cv2
import numpy as np
from fastapi import APIRouter, Depends, File, Form, UploadFile

from app.api.deps import get_services, require_detector
from app.errors import ApiError, ServiceUnavailableError
from app.schemas.common import BoundingBox, ErrorResponse, FrameInfo
from app.schemas.items import (
    ItemMatchResponse,
    MatchCandidate,
    MatchDecision,
    MatchStatus,
    ReferenceQualityResponse,
)
from app.services.registry import Services
from app.services.spatial import relative_position
from app.utils.image_io import crop, load_upload

router = APIRouter(prefix="/api/v1/items", tags=["personal items"])

ERRORS = {413: {"model": ErrorResponse}, 415: {"model": ErrorResponse}, 422: {"model": ErrorResponse},
          503: {"model": ErrorResponse}, 504: {"model": ErrorResponse}}
CROP_PAD = 0.08
MIN_BLUR_VARIANCE = 40.0


def _check_label(label: str, services: Services) -> None:
    if label not in services.detector.classes:
        raise ApiError(
            422, "unsupported_class",
            f"'{label}' is not a class the detector can recognise, so it cannot be located.",
            {"supported_classes": services.detector.classes},
        )


def _largest_instance(rgb: np.ndarray, label: str, services: Services):
    out = services.detector.detect(rgb, confidence=0.25, classes=[label])
    if not out.detections:
        return None
    return max(out.detections, key=lambda d: (d.x2 - d.x1) * (d.y2 - d.y1))


def _reference_crops(refs: list[np.ndarray], label: str, services: Services) -> tuple[list[np.ndarray], list[str]]:
    crops, notes = [], []
    for i, ref in enumerate(refs):
        d = _largest_instance(ref, label, services)
        if d is None:
            h, w = ref.shape[:2]
            crops.append(ref[int(h * 0.1):int(h * 0.9), int(w * 0.1):int(w * 0.9)])
            notes.append(f"reference {i + 1}: no {label} detected, used the central area")
        else:
            crops.append(crop(ref, d.x1, d.y1, d.x2, d.y2, CROP_PAD))
    return crops, notes


@router.post("/match", response_model=ItemMatchResponse, responses=ERRORS,
             summary="Find a registered personal item in a scene")
async def match(
    image: UploadFile = File(..., description="Scene image to search."),
    references: list[UploadFile] = File(..., description="1-5 reference photos of the registered item."),
    item_label: str = Form(..., max_length=64, description="Detector class of the item, e.g. 'cell phone'."),
    item_name: str | None = Form(None, max_length=80, description="User's name for the item (echoed back only)."),
    frame_id: str | None = Form(None, max_length=64),
    services: Services = Depends(get_services),
) -> ItemMatchResponse:
    """1) YOLOv8 finds candidates of ``item_label``; 2) each candidate crop is compared
    with the reference photos by the configured matcher; 3) thresholds decide.

    Reference photos are processed in memory and not stored by the server.
    """
    require_detector(services)
    if not services.matcher.is_ready():
        raise ServiceUnavailableError("The personal-item matcher is not available.")
    _check_label(item_label, services)
    s = services.settings
    if not 1 <= len(references) <= s.item_max_references:
        raise ApiError(422, "validation_error", f"Provide between 1 and {s.item_max_references} reference photos.")

    scene = await load_upload(image, s)
    refs = [(await load_upload(r, s, f"references[{i}]")).rgb for i, r in enumerate(references)]
    frame = FrameInfo(width=scene.width, height=scene.height, frame_id=frame_id)
    thresholds = {"match": s.item_match_threshold, "possible_match": s.item_possible_match_threshold}

    def work():
        ref_crops, notes = _reference_crops(refs, item_label, services)
        out = services.detector.detect(scene.rgb, confidence=0.25, classes=[item_label])
        cands = []
        for d in out.detections[:8]:
            sim, parts = services.matcher.similarity(crop(scene.rgb, d.x1, d.y1, d.x2, d.y2, CROP_PAD), ref_crops)
            cands.append((d, sim, parts))
        return cands, notes

    raw, notes = await services.gate.run(work)
    candidates: list[MatchCandidate] = []
    for d, sim, parts in raw:
        decision = (MatchDecision.MATCH if sim >= thresholds["match"]
                    else MatchDecision.POSSIBLE_MATCH if sim >= thresholds["possible_match"]
                    else MatchDecision.NO_MATCH)
        bbox = BoundingBox(x1=round(d.x1, 1), y1=round(d.y1, 1), x2=round(d.x2, 1), y2=round(d.y2, 1))
        candidates.append(MatchCandidate(
            detection_label=d.label, detection_confidence=round(d.confidence, 3), bbox=bbox,
            position=relative_position(bbox, frame, s.camera_fov_degrees), similarity=sim,
            similarity_components=parts, decision=decision,
        ))
    candidates.sort(key=lambda c: c.similarity, reverse=True)
    best = candidates[0] if candidates else None
    name = item_name or f"your {item_label}"

    if best is None:
        status, msg = MatchStatus.NO_CANDIDATES, f"I can't see any {item_label} in this view."
    elif best.decision == MatchDecision.MATCH:
        status = MatchStatus.FOUND
        msg = f"This looks like {name}, {best.position.description.split(',')[0]}, at {best.position.clock_label}."
    elif best.decision == MatchDecision.POSSIBLE_MATCH:
        status = MatchStatus.POSSIBLY_FOUND
        msg = (f"A {item_label} that might be {name} is {best.position.description.split(',')[0]}, "
               f"at {best.position.clock_label}. Please check it.")
    else:
        status = MatchStatus.NOT_FOUND
        count = f"a {item_label}" if len(candidates) == 1 else f"{len(candidates)} of type {item_label}"
        msg = f"I can see {count}, but it doesn't look like {name}."

    notes += [
        "Similarity thresholds are uncalibrated defaults; evaluate with your own photos.",
        "Items of the same model and colour may be indistinguishable.",
    ]
    return ItemMatchResponse(
        status=status, item_name=item_name, item_label=item_label, frame=frame, best=best,
        candidates=candidates, message=msg, matcher=services.matcher.info, thresholds=thresholds, notes=notes,
    )


@router.post("/check-reference", response_model=ReferenceQualityResponse, responses=ERRORS,
             summary="Check a reference photo when registering an item")
async def check_reference(
    image: UploadFile = File(...),
    item_label: str = Form(..., max_length=64),
    services: Services = Depends(get_services),
) -> ReferenceQualityResponse:
    """Checks that the item class is visible, large enough, sharp and well lit."""
    require_detector(services)
    _check_label(item_label, services)
    img = await load_upload(image, services.settings)
    d = await services.gate.run(_largest_instance, img.rgb, item_label, services)
    issues: list[str] = []
    bbox = None
    if d is None:
        issues.append(f"No {item_label} was detected. Place it in the centre with a plain background.")
    else:
        bbox = BoundingBox(x1=round(d.x1, 1), y1=round(d.y1, 1), x2=round(d.x2, 1), y2=round(d.y2, 1))
        if bbox.area / (img.width * img.height) < 0.05:
            issues.append("The item is small in the photo. Move the camera closer.")
    gray = cv2.cvtColor(img.rgb, cv2.COLOR_RGB2GRAY)
    if cv2.Laplacian(gray, cv2.CV_64F).var() < MIN_BLUR_VARIANCE:
        issues.append("The photo looks blurry. Hold the camera still.")
    mean = float(gray.mean())
    if mean < 40:
        issues.append("The photo is too dark.")
    elif mean > 225:
        issues.append("The photo is over-exposed.")
    accepted = d is not None and not issues
    return ReferenceQualityResponse(
        accepted=accepted, item_label=item_label, detected=d is not None,
        detection_confidence=round(d.confidence, 3) if d else None, bbox=bbox, issues=issues,
        message="Reference photo looks good." if accepted else " ".join(issues),
    )
