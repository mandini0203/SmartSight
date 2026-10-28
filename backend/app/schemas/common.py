"""Shared Pydantic models used across endpoints."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field, model_validator


class BoundingBox(BaseModel):
    """Axis-aligned box in pixel coordinates of the analysed frame."""

    x1: float = Field(..., ge=0)
    y1: float = Field(..., ge=0)
    x2: float = Field(..., ge=0)
    y2: float = Field(..., ge=0)

    @model_validator(mode="after")
    def _ordered(self) -> "BoundingBox":
        if self.x2 <= self.x1 or self.y2 <= self.y1:
            raise ValueError("bounding box must satisfy x2 > x1 and y2 > y1")
        return self

    @property
    def width(self) -> float:
        return self.x2 - self.x1

    @property
    def height(self) -> float:
        return self.y2 - self.y1

    @property
    def area(self) -> float:
        return self.width * self.height

    @property
    def centre(self) -> tuple[float, float]:
        return (self.x1 + self.x2) / 2, (self.y1 + self.y2) / 2


class FrameInfo(BaseModel):
    width: int = Field(..., gt=0, le=20000)
    height: int = Field(..., gt=0, le=20000)
    frame_id: str | None = Field(None, max_length=64)
    captured_at: datetime | None = None


class Horizontal(str, Enum):
    LEFT = "left"
    SLIGHTLY_LEFT = "slightly_left"
    CENTRE = "centre"
    SLIGHTLY_RIGHT = "slightly_right"
    RIGHT = "right"


class Vertical(str, Enum):
    UPPER = "upper"
    MIDDLE = "middle"
    LOWER = "lower"


class ApparentSize(str, Enum):
    """Size of the box relative to the frame. A cue for proximity, not a distance."""

    LARGE = "large"
    MEDIUM = "medium"
    SMALL = "small"


class RelativePosition(BaseModel):
    horizontal: Horizontal
    vertical: Vertical
    clock_direction: int = Field(..., ge=9, le=15, description="9..15 where 12 is straight ahead; 13 = 1 o'clock etc.")
    clock_label: str = Field(..., description="Human-readable clock face direction, e.g. '1 o'clock'.")
    apparent_size: ApparentSize
    area_ratio: float = Field(..., ge=0, le=1)
    description: str


class DistanceEstimate(BaseModel):
    """Approximate absolute distance. Always an estimate with a range."""

    metres: float = Field(..., gt=0)
    low_metres: float = Field(..., gt=0)
    high_metres: float = Field(..., gt=0)
    confidence: float = Field(..., ge=0, le=1)
    method: str
    assumptions: list[str]


class ComponentInfo(BaseModel):
    """Identifies which implementation produced a result."""

    name: str
    version: str
    is_trained_model: bool
    description: str


class ErrorBody(BaseModel):
    code: str
    message: str
    details: Any = None


class ErrorResponse(BaseModel):
    error: ErrorBody
    request_id: str | None = None
