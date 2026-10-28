"""Pretrained YOLOv8 object detector (Ultralytics, COCO-80 classes).

This runs real inference with the checkpoint configured by
``SMARTSIGHT_MODEL_PATH``. It never fabricates detections: if the model cannot
be loaded the detector reports not-ready and the API returns 503.
"""

from __future__ import annotations

import hashlib
import logging
import os
import threading
import time
from pathlib import Path

import numpy as np

# Stop Ultralytics from silently pip-installing packages at runtime.
os.environ.setdefault("YOLO_AUTOINSTALL", "False")
os.environ.setdefault("YOLO_OFFLINE", "True")

from app.schemas.detection import ModelInfo  # noqa: E402
from app.services.interfaces import DetectorOutput, ObjectDetector, RawDetection  # noqa: E402

logger = logging.getLogger("smartsight.detector")


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


class YoloV8Detector(ObjectDetector):
    def __init__(
        self,
        model_path: Path,
        *,
        confidence: float,
        iou: float,
        image_size: int,
        max_results: int,
        device: str,
    ) -> None:
        self.model_path = Path(model_path)
        self.default_confidence = confidence
        self.iou = iou
        self.image_size = image_size
        self.max_results = max_results
        self.device = device
        self._model = None
        self._names: dict[int, str] = {}
        self._lock = threading.Lock()
        self.load_error: str | None = None
        self.sha256: str | None = None

    # -- lifecycle -------------------------------------------------------
    def load(self) -> None:
        if not self.model_path.is_file():
            self.load_error = (
                f"Model file not found at {self.model_path}. "
                "Run `python scripts/download_models.py` (see README)."
            )
            logger.error(self.load_error)
            return
        try:
            from ultralytics import YOLO

            model = YOLO(str(self.model_path), task="detect")
            self._names = {int(k): str(v) for k, v in model.names.items()}
            self._model = model
            self.sha256 = file_sha256(self.model_path)
            self.load_error = None
            logger.info("Loaded %s (%d classes)", self.model_path.name, len(self._names))
        except Exception as exc:  # pragma: no cover - depends on environment
            self.load_error = f"Failed to load model: {exc}"
            logger.exception("Failed to load YOLOv8 model")

    def warmup(self) -> None:
        if self._model is not None:
            self.detect(np.zeros((self.image_size, self.image_size, 3), dtype=np.uint8))

    # -- ObjectDetector ----------------------------------------------------
    def is_ready(self) -> bool:
        return self._model is not None

    @property
    def classes(self) -> list[str]:
        return [self._names[i] for i in sorted(self._names)]

    @property
    def info(self) -> ModelInfo:
        return ModelInfo(
            name="YOLOv8n (pretrained)" if "yolov8n" in self.model_path.name else "YOLOv8 (pretrained)",
            version=self.model_path.stem,
            is_trained_model=True,
            description=(
                "Ultralytics YOLOv8 pretrained on COCO 2017. Not fine-tuned for SmartSight; "
                "recognises only its 80 COCO classes."
            ),
            model_file=self.model_path.name,
            dataset="COCO 2017 (80 classes)",
            licence="AGPL-3.0 (Ultralytics); commercial use requires an Ultralytics Enterprise licence",
            num_classes=len(self._names),
        )

    def detect(
        self,
        image: np.ndarray,
        *,
        confidence: float | None = None,
        classes: list[str] | None = None,
    ) -> DetectorOutput:
        if self._model is None:
            raise RuntimeError(self.load_error or "Detector not loaded")
        class_ids = None
        if classes:
            lookup = {v: k for k, v in self._names.items()}
            class_ids = [lookup[c] for c in classes if c in lookup]
            if not class_ids:
                return DetectorOutput([], int(image.shape[1]), int(image.shape[0]), {"total": 0.0})

        # Ultralytics expects BGR for numpy input.
        bgr = np.ascontiguousarray(image[:, :, ::-1])
        start = time.perf_counter()
        with self._lock:
            results = self._model.predict(
                bgr,
                conf=confidence if confidence is not None else self.default_confidence,
                iou=self.iou,
                imgsz=self.image_size,
                max_det=self.max_results,
                classes=class_ids,
                device=self.device,
                verbose=False,
            )
        total_ms = (time.perf_counter() - start) * 1000
        result = results[0]
        h, w = result.orig_shape
        dets: list[RawDetection] = []
        boxes = result.boxes
        if boxes is not None and len(boxes):
            xyxy = boxes.xyxy.cpu().numpy()
            confs = boxes.conf.cpu().numpy()
            cls = boxes.cls.cpu().numpy().astype(int)
            for (x1, y1, x2, y2), p, c in zip(xyxy, confs, cls):
                x1, x2 = float(np.clip(x1, 0, w)), float(np.clip(x2, 0, w))
                y1, y2 = float(np.clip(y1, 0, h)), float(np.clip(y2, 0, h))
                if x2 - x1 < 1 or y2 - y1 < 1:
                    continue
                dets.append(RawDetection(self._names[int(c)], int(c), float(p), x1, y1, x2, y2))
        dets.sort(key=lambda d: d.confidence, reverse=True)
        timings = {k: float(v) for k, v in (result.speed or {}).items()}
        timings["total"] = total_ms
        return DetectorOutput(dets, int(w), int(h), timings)
