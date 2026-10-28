"""Stable service interfaces.

Routes depend only on these abstractions. The initial implementations are a
pretrained YOLOv8 detector plus deterministic rule-based / classical
image-processing components. Future trained models can be added as new
implementations and selected through configuration (see ``registry.py``)
without changing routes or schemas.

Images passed to every interface are ``numpy.ndarray`` of shape (H, W, 3),
dtype uint8, RGB channel order, EXIF orientation already applied.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field

import numpy as np

from app.schemas.colour import ColourResponse
from app.schemas.common import BoundingBox, ComponentInfo, DistanceEstimate, FrameInfo
from app.schemas.context import ContextRequest, ContextResponse
from app.schemas.detection import ModelInfo
from app.schemas.intent import IntentRequest, IntentResponse


@dataclass(frozen=True)
class RawDetection:
    label: str
    class_id: int
    confidence: float
    x1: float
    y1: float
    x2: float
    y2: float


@dataclass
class DetectorOutput:
    detections: list[RawDetection]
    width: int
    height: int
    timings_ms: dict[str, float] = field(default_factory=dict)


class ObjectDetector(ABC):
    """General object detector.

    Input: RGB image. Output: boxes in pixel coordinates of the input image,
    labels drawn only from ``classes``, confidences in [0, 1].
    """

    @property
    @abstractmethod
    def info(self) -> ModelInfo: ...

    @property
    @abstractmethod
    def classes(self) -> list[str]: ...

    @abstractmethod
    def is_ready(self) -> bool: ...

    @abstractmethod
    def detect(
        self,
        image: np.ndarray,
        *,
        confidence: float | None = None,
        classes: list[str] | None = None,
    ) -> DetectorOutput: ...


@dataclass
class RawSignCandidate:
    kind: str  # "exit_sign" | "door"
    confidence: float
    detector_confidence: float | None
    box: tuple[float, float, float, float]
    evidence: list[str]
    sign_colour: str | None = None


class DoorSignDetector(ABC):
    @property
    @abstractmethod
    def info(self) -> ComponentInfo: ...

    @abstractmethod
    def is_ready(self) -> bool: ...

    @property
    @abstractmethod
    def supported_kinds(self) -> list[str]: ...

    @abstractmethod
    def detect(self, image: np.ndarray) -> list[RawSignCandidate]: ...


class DistanceEstimator(ABC):
    """Absolute distance from camera to an object. Returns None when it cannot estimate."""

    @property
    @abstractmethod
    def info(self) -> ComponentInfo: ...

    @abstractmethod
    def estimate(
        self, label: str, bbox: BoundingBox, frame: FrameInfo, fov_degrees: float | None = None
    ) -> DistanceEstimate | None: ...


class ContextReasoner(ABC):
    @property
    @abstractmethod
    def info(self) -> ComponentInfo: ...

    @abstractmethod
    def analyse(self, request: ContextRequest, fov_degrees: float | None = None) -> ContextResponse: ...


class IntentResolver(ABC):
    @property
    @abstractmethod
    def info(self) -> ComponentInfo: ...

    @abstractmethod
    def resolve(self, request: IntentRequest) -> IntentResponse: ...


class PersonalItemMatcher(ABC):
    """Compares a candidate crop with reference crops of one registered item.

    Returns an overall similarity in [0, 1] and named component scores.
    """

    @property
    @abstractmethod
    def info(self) -> ComponentInfo: ...

    @abstractmethod
    def is_ready(self) -> bool: ...

    @abstractmethod
    def similarity(
        self, candidate: np.ndarray, references: list[np.ndarray]
    ) -> tuple[float, dict[str, float]]: ...


class ColourIdentifier(ABC):
    @property
    @abstractmethod
    def info(self) -> ComponentInfo: ...

    @abstractmethod
    def identify(
        self, image: np.ndarray, region: BoundingBox, region_source: str, frame: FrameInfo
    ) -> ColourResponse: ...
