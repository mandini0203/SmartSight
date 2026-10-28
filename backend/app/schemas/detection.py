from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.common import (
    BoundingBox,
    ComponentInfo,
    DistanceEstimate,
    FrameInfo,
    RelativePosition,
)


class Detection(BaseModel):
    id: int = Field(..., ge=0, description="Index of the detection within this frame.")
    label: str
    class_id: int = Field(..., ge=0)
    confidence: float = Field(..., ge=0, le=1)
    bbox: BoundingBox
    bbox_normalised: BoundingBox = Field(..., description="Box divided by frame width/height (0..1).")
    position: RelativePosition | None = None
    distance: DistanceEstimate | None = None


class ModelInfo(ComponentInfo):
    model_file: str
    task: str = "detect"
    dataset: str
    licence: str
    num_classes: int


class ProcessingInfo(BaseModel):
    preprocess_ms: float | None = None
    inference_ms: float | None = None
    postprocess_ms: float | None = None
    total_ms: float
    confidence_threshold: float
    image_size: int
    device: str


class DetectionResponse(BaseModel):
    frame: FrameInfo
    timestamp: datetime
    detections: list[Detection]
    model: ModelInfo
    processing: ProcessingInfo
    notes: list[str] = Field(default_factory=list)


class SupportedClassesResponse(BaseModel):
    model: ModelInfo
    classes: list[str]
    notes: list[str]
