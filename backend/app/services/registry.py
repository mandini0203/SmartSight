"""Builds the service implementations selected by configuration.

To add a trained model later, implement the relevant interface in
``interfaces.py``, add a new option to the matching ``Settings`` field and
construct it here. The rule-based implementations stay available as the
baseline for comparison.
"""

from __future__ import annotations

import asyncio
import logging
import threading
from dataclasses import dataclass, field
from typing import Callable, TypeVar

from starlette.concurrency import run_in_threadpool

from app.config import Settings
from app.errors import InferenceTimeoutError, ServiceUnavailableError
from app.services.colour.kmeans_lab import KMeansLabColourIdentifier
from app.services.context.rule_based import RuleBasedContextReasoner
from app.services.detection.yolo_detector import YoloV8Detector
from app.services.distance import KnownSizeDistanceEstimator
from app.services.intent.rule_based import RuleBasedIntentResolver
from app.services.interfaces import (
    ColourIdentifier,
    ContextReasoner,
    DistanceEstimator,
    DoorSignDetector,
    IntentResolver,
    ObjectDetector,
    PersonalItemMatcher,
)
from app.services.items.matcher import ClassicalItemMatcher, EmbeddingItemMatcher
from app.services.signs.detector import HeuristicExitSignDetector, YoloWorldDoorSignDetector

logger = logging.getLogger("smartsight.registry")
T = TypeVar("T")


class InferenceGate:
    """Bounded queue in front of CPU-heavy inference.

    At most ``max_waiting`` requests may wait; further requests are rejected
    with 503 instead of piling up (the phone should then retry later). Each
    call has a timeout. Python threads cannot be killed, so a timed-out call
    still finishes in the background, but the client gets a prompt 504.
    """

    def __init__(self, max_concurrent: int = 1, max_waiting: int = 4, timeout_s: float = 20.0) -> None:
        self._sem = asyncio.Semaphore(max_concurrent)
        self._waiting = 0
        self._max_waiting = max_waiting
        self._timeout = timeout_s
        self._counter_lock = threading.Lock()

    async def run(self, fn: Callable[..., T], *args, **kwargs) -> T:
        with self._counter_lock:
            if self._waiting >= self._max_waiting:
                raise ServiceUnavailableError("The server is busy processing other images. Please retry shortly.")
            self._waiting += 1
        try:
            async with self._sem:
                try:
                    return await asyncio.wait_for(run_in_threadpool(fn, *args, **kwargs), self._timeout)
                except asyncio.TimeoutError as exc:
                    raise InferenceTimeoutError(f"Image analysis took longer than {self._timeout:.0f} s.") from exc
        finally:
            with self._counter_lock:
                self._waiting -= 1


@dataclass
class Services:
    settings: Settings
    detector: ObjectDetector
    door_sign: DoorSignDetector
    distance: DistanceEstimator | None
    context: ContextReasoner
    intent: IntentResolver
    colour: ColourIdentifier
    matcher: PersonalItemMatcher
    gate: InferenceGate
    load_errors: dict[str, str] = field(default_factory=dict)


def build_services(settings: Settings) -> Services:
    errors: dict[str, str] = {}

    detector = YoloV8Detector(
        settings.model_path,
        confidence=settings.detection_confidence,
        iou=settings.detection_iou,
        image_size=settings.detection_image_size,
        max_results=settings.detection_max_results,
        device=settings.inference_device,
    )
    detector.load()
    if detector.load_error:
        errors["detector"] = detector.load_error
    elif settings.warmup_on_startup:
        detector.warmup()

    door_sign: DoorSignDetector
    if settings.door_sign_backend == "yolo_world":
        yw = YoloWorldDoorSignDetector(
            settings.door_sign_model_path, settings.door_sign_confidence,
            settings.detection_image_size, settings.inference_device,
        )
        yw.load()
        if yw.is_ready():
            door_sign = yw
        else:
            errors["door_sign"] = f"{yw.load_error}; using colour heuristic fallback (exit signs only)"
            door_sign = HeuristicExitSignDetector()
    else:
        door_sign = HeuristicExitSignDetector()

    matcher: PersonalItemMatcher
    if settings.item_matcher == "embedding":
        emb = EmbeddingItemMatcher(str(settings.model_path.parent / "torch" / "hub"))
        emb.load()
        if emb.is_ready():
            matcher = emb
        else:
            errors["item_matcher"] = f"{emb.load_error}; using ORB/colour fallback"
            matcher = ClassicalItemMatcher()
    else:
        matcher = ClassicalItemMatcher()

    distance = (
        KnownSizeDistanceEstimator(settings.camera_fov_degrees)
        if settings.distance_estimation_enabled else None
    )
    classes = detector.classes if detector.is_ready() else []
    for name, msg in errors.items():
        logger.warning("%s: %s", name, msg)

    return Services(
        settings=settings,
        detector=detector,
        door_sign=door_sign,
        distance=distance,
        context=RuleBasedContextReasoner(distance, settings.camera_fov_degrees, classes),
        intent=RuleBasedIntentResolver(classes),
        colour=KMeansLabColourIdentifier(),
        matcher=matcher,
        gate=InferenceGate(timeout_s=settings.inference_timeout_seconds),
        load_errors=errors,
    )
