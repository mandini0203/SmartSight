from __future__ import annotations

from enum import Enum

from pydantic import BaseModel, Field

from app.schemas.common import BoundingBox, ComponentInfo, DistanceEstimate, FrameInfo, RelativePosition


class TaskType(str, Enum):
    DESCRIBE_SURROUNDINGS = "describe_surroundings"
    FIND_OBJECT = "find_object"
    FIND_SEAT = "find_seat"
    FIND_EXIT = "find_exit"
    IDENTIFY_COLOUR = "identify_colour"


class InputDetection(BaseModel):
    """A detection supplied to the context engine (normally from /detection)."""

    id: int | None = Field(None, ge=0)
    label: str = Field(..., min_length=1, max_length=64)
    confidence: float = Field(..., ge=0, le=1)
    bbox: BoundingBox


class ContextRequest(BaseModel):
    frame: FrameInfo
    detections: list[InputDetection] = Field(default_factory=list, max_length=300)
    task: TaskType = TaskType.DESCRIBE_SURROUNDINGS
    target_label: str | None = Field(
        None, max_length=64, description="COCO label to look for when task is find_object."
    )


class RelationshipType(str, Enum):
    ON_TOP_OF = "on_top_of"
    OCCUPYING = "occupying"
    NEXT_TO = "next_to"
    LEFT_OF = "left_of"
    RIGHT_OF = "right_of"
    IN_FRONT_OF = "in_front_of"


class Relationship(BaseModel):
    """A candidate relationship inferred by rules. Not a verified fact."""

    type: RelationshipType
    subject_id: int
    subject_label: str
    object_id: int
    object_label: str
    confidence: float = Field(..., ge=0, le=1)
    evidence: list[str]


class SeatStatus(str, Enum):
    LIKELY_OCCUPIED = "LIKELY_OCCUPIED"
    POTENTIALLY_UNOCCUPIED = "POTENTIALLY_UNOCCUPIED"
    UNCERTAIN = "UNCERTAIN"


class SeatAssessment(BaseModel):
    detection_id: int
    label: str
    status: SeatStatus
    confidence: float = Field(..., ge=0, le=1)
    evidence: list[str]
    position: RelativePosition


class AnalysedObject(BaseModel):
    id: int
    label: str
    confidence: float
    bbox: BoundingBox
    position: RelativePosition
    distance: DistanceEstimate | None = None


class Guidance(BaseModel):
    message: str = Field(..., description="Short sentence suitable for text-to-speech.")
    details: list[str] = Field(default_factory=list)
    confidence: float = Field(..., ge=0, le=1)
    evidence: list[str]
    target_ids: list[int] = Field(default_factory=list)


class ContextResponse(BaseModel):
    task: TaskType
    frame: FrameInfo
    objects: list[AnalysedObject]
    relevant_object_ids: list[int]
    relationships: list[Relationship]
    seats: list[SeatAssessment]
    guidance: Guidance
    reasoner: ComponentInfo
    disclaimer: str
