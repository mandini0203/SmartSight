from __future__ import annotations

from datetime import datetime
from enum import Enum

from pydantic import BaseModel, Field

from app.schemas.common import BoundingBox, ComponentInfo, DistanceEstimate, FrameInfo, RelativePosition


class SignKind(str, Enum):
    EXIT_SIGN = "exit_sign"
    DOOR = "door"


class SignCandidate(BaseModel):
    kind: SignKind
    confidence: float = Field(..., ge=0, le=1, description="Combined confidence after verification checks.")
    detector_confidence: float | None = Field(None, ge=0, le=1)
    bbox: BoundingBox
    position: RelativePosition
    distance: DistanceEstimate | None = None
    evidence: list[str]
    sign_colour: str | None = None


class SignsResponse(BaseModel):
    frame: FrameInfo
    timestamp: datetime
    candidates: list[SignCandidate]
    message: str
    detector: ComponentInfo
    processing_ms: float
    notes: list[str]
