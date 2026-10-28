from __future__ import annotations

from enum import Enum

from pydantic import BaseModel, Field

from app.schemas.common import BoundingBox, ComponentInfo, FrameInfo, RelativePosition


class MatchDecision(str, Enum):
    MATCH = "MATCH"
    POSSIBLE_MATCH = "POSSIBLE_MATCH"
    NO_MATCH = "NO_MATCH"


class MatchStatus(str, Enum):
    FOUND = "FOUND"
    POSSIBLY_FOUND = "POSSIBLY_FOUND"
    NOT_FOUND = "NOT_FOUND"
    NO_CANDIDATES = "NO_CANDIDATES"


class MatchCandidate(BaseModel):
    detection_label: str
    detection_confidence: float
    bbox: BoundingBox
    position: RelativePosition
    similarity: float = Field(..., ge=0, le=1)
    similarity_components: dict[str, float]
    decision: MatchDecision


class ItemMatchResponse(BaseModel):
    status: MatchStatus
    item_name: str | None
    item_label: str
    frame: FrameInfo
    best: MatchCandidate | None
    candidates: list[MatchCandidate]
    message: str
    matcher: ComponentInfo
    thresholds: dict[str, float]
    notes: list[str]


class ReferenceQualityResponse(BaseModel):
    """Result of checking a reference photo when an item is registered."""

    accepted: bool
    item_label: str
    detected: bool
    detection_confidence: float | None
    bbox: BoundingBox | None
    issues: list[str]
    message: str
