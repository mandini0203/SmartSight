"""Door and exit-sign candidate detection.

COCO-pretrained YOLOv8 has no "door" or "exit sign" class, so this component
is separate from the main detector:

* ``YoloWorldDoorSignDetector`` - pretrained open-vocabulary YOLOv8-World
  (``yolov8s-worldv2.pt``) prompted with the text classes "door" and
  "exit sign" (CLIP text embeddings computed once at load). Not fine-tuned.
  Every box is then checked with transparent colour/shape rules, and the final
  confidence combines both.
* ``HeuristicExitSignDetector`` - OpenCV-only fallback that finds bright,
  saturated green or red rectangles typical of illuminated exit signs. It does
  not detect doors.

Outputs are *candidates* for the user to confirm, never guaranteed exits.
"""

from __future__ import annotations

import logging
import os
import threading
from pathlib import Path

import cv2
import numpy as np

os.environ.setdefault("YOLO_AUTOINSTALL", "False")
os.environ.setdefault("YOLO_OFFLINE", "True")

from app.schemas.common import ComponentInfo  # noqa: E402
from app.services.interfaces import DoorSignDetector, RawSignCandidate  # noqa: E402

logger = logging.getLogger("smartsight.signs")

PROMPTS = {"exit sign": "exit_sign", "door": "door"}


def sign_colour_evidence(rgb_patch: np.ndarray) -> tuple[float, str | None, list[str]]:
    """Fraction of bright saturated green / red pixels typical of exit signs."""
    if rgb_patch.size == 0:
        return 0.0, None, ["empty region"]
    hsv = cv2.cvtColor(rgb_patch, cv2.COLOR_RGB2HSV)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    vivid = (s >= 90) & (v >= 90)
    green = vivid & (h >= 40) & (h <= 90)
    red = vivid & ((h <= 8) | (h >= 170))
    white = (s < 50) & (v >= 180)
    g, r, w = float(green.mean()), float(red.mean()), float(white.mean())
    colour = "green" if g >= r else "red"
    frac = max(g, r)
    evidence = [f"{frac:.0%} of the region is vivid {colour}"]
    if w > 0.05:
        evidence.append(f"{w:.0%} bright white pixels (lettering or pictogram)")
    score = float(np.clip(frac / 0.35, 0, 1)) * (1.0 if w > 0.03 else 0.8)
    return score, (colour if frac >= 0.1 else None), evidence


def _aspect_score_exit(w: float, h: float) -> tuple[float, str]:
    ar = w / max(h, 1e-6)
    ok = 1.2 <= ar <= 5.0
    return (1.0 if ok else 0.4), f"width/height ratio {ar:.1f} ({'typical' if ok else 'atypical'} for an exit sign)"


def _aspect_score_door(w: float, h: float, frame_h: int) -> tuple[float, list[str]]:
    ar = h / max(w, 1e-6)
    ok = 1.5 <= ar <= 3.8
    tall = h / frame_h
    ev = [f"height/width ratio {ar:.1f} ({'typical' if ok else 'atypical'} for a door)",
          f"spans {tall:.0%} of the image height"]
    return (1.0 if ok else 0.5) * (1.0 if tall >= 0.3 else 0.7), ev


class YoloWorldDoorSignDetector(DoorSignDetector):
    def __init__(self, model_path: Path, confidence: float, image_size: int, device: str) -> None:
        self.model_path = Path(model_path)
        self.confidence = confidence
        self.image_size = image_size
        self.device = device
        self._model = None
        self._names: dict[int, str] = {}
        self._lock = threading.Lock()
        self.load_error: str | None = None

    def load(self) -> None:
        if not self.model_path.is_file():
            self.load_error = f"YOLO-World model not found at {self.model_path}"
            logger.warning(self.load_error)
            return
        clip_dir = self.model_path.parent / "clip"
        if not (clip_dir / "ViT-B-32.pt").is_file():
            self.load_error = f"CLIP text encoder weights not found in {clip_dir}"
            logger.warning(self.load_error)
            return
        try:
            import ultralytics.nn.text_model as text_model
            from ultralytics import YOLOWorld

            text_model.WEIGHTS_DIR = self.model_path.parent  # keep CLIP weights inside models/
            model = YOLOWorld(str(self.model_path))
            model.set_classes(list(PROMPTS))
            self._names = {int(k): str(v) for k, v in model.names.items()}
            self._model = model
            self.load_error = None
            logger.info("Loaded YOLO-World door/sign detector")
        except Exception as exc:  # pragma: no cover - environment dependent
            self.load_error = f"Failed to load YOLO-World: {exc}"
            logger.exception("Failed to load YOLO-World")

    @property
    def info(self) -> ComponentInfo:
        return ComponentInfo(
            name="yolo_world_door_sign",
            version=self.model_path.stem,
            is_trained_model=True,
            description=(
                "Pretrained open-vocabulary YOLOv8-World prompted with 'door' and 'exit sign' "
                "(not fine-tuned), verified by colour and shape rules."
            ),
        )

    @property
    def supported_kinds(self) -> list[str]:
        return ["exit_sign", "door"]

    def is_ready(self) -> bool:
        return self._model is not None

    def detect(self, image: np.ndarray) -> list[RawSignCandidate]:
        if self._model is None:
            raise RuntimeError(self.load_error or "Door/sign detector not loaded")
        bgr = np.ascontiguousarray(image[:, :, ::-1])
        with self._lock:
            result = self._model.predict(bgr, conf=self.confidence, imgsz=self.image_size,
                                         device=self.device, verbose=False)[0]
        h, w = image.shape[:2]
        out: list[RawSignCandidate] = []
        if result.boxes is None:
            return out
        for (x1, y1, x2, y2), p, c in zip(result.boxes.xyxy.cpu().numpy(), result.boxes.conf.cpu().numpy(),
                                          result.boxes.cls.cpu().numpy().astype(int)):
            x1, x2 = float(np.clip(x1, 0, w)), float(np.clip(x2, 0, w))
            y1, y2 = float(np.clip(y1, 0, h)), float(np.clip(y2, 0, h))
            if x2 - x1 < 4 or y2 - y1 < 4:
                continue
            kind = PROMPTS[self._names[int(c)]]
            det_conf = float(p)
            evidence = [f"YOLO-World '{self._names[int(c)]}' score {det_conf:.2f}"]
            colour = None
            if kind == "exit_sign":
                patch = image[int(y1):int(np.ceil(y2)), int(x1):int(np.ceil(x2))]
                cscore, colour, cev = sign_colour_evidence(patch)
                ascore, aev = _aspect_score_exit(x2 - x1, y2 - y1)
                evidence += cev + [aev]
                verify = 0.7 * cscore + 0.3 * ascore
                combined = det_conf * (0.4 + 0.6 * verify)
                if cscore < 0.2:
                    evidence.append("no typical green/red exit-sign colour; weak candidate")
            else:
                ascore, aev = _aspect_score_door(x2 - x1, y2 - y1, h)
                evidence += aev
                combined = det_conf * (0.5 + 0.5 * ascore)
            out.append(RawSignCandidate(kind, round(float(min(combined, 0.95)), 2), round(det_conf, 3),
                                        (x1, y1, x2, y2), evidence, colour))
        out.sort(key=lambda c: c.confidence, reverse=True)
        return out


class HeuristicExitSignDetector(DoorSignDetector):
    @property
    def info(self) -> ComponentInfo:
        return ComponentInfo(
            name="heuristic_exit_sign",
            version="1.0",
            is_trained_model=False,
            description="OpenCV colour/shape heuristic for illuminated green or red exit signs. Doors not supported.",
        )

    @property
    def supported_kinds(self) -> list[str]:
        return ["exit_sign"]

    def is_ready(self) -> bool:
        return True

    def detect(self, image: np.ndarray) -> list[RawSignCandidate]:
        h, w = image.shape[:2]
        hsv = cv2.cvtColor(image, cv2.COLOR_RGB2HSV)
        hh, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
        vivid = (s >= 110) & (v >= 120)
        masks = {
            "green": (vivid & (hh >= 40) & (hh <= 90)).astype(np.uint8) * 255,
            "red": (vivid & ((hh <= 8) | (hh >= 170))).astype(np.uint8) * 255,
        }
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
        out: list[RawSignCandidate] = []
        for colour, mask in masks.items():
            mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=2)
            contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            for cnt in contours:
                x, y, bw, bh = cv2.boundingRect(cnt)
                if bw * bh < 0.001 * w * h:
                    continue
                fill = cv2.contourArea(cnt) / float(bw * bh)
                ascore, aev = _aspect_score_exit(bw, bh)
                if fill < 0.5 or ascore < 1.0:
                    continue
                cscore, _, cev = sign_colour_evidence(image[y:y + bh, x:x + bw])
                conf = round(0.45 * (0.5 * cscore + 0.5 * fill), 2)
                out.append(RawSignCandidate(
                    "exit_sign", conf, None, (float(x), float(y), float(x + bw), float(y + bh)),
                    [f"vivid {colour} rectangle, {fill:.0%} filled", aev, *cev,
                     "colour heuristic only; many green/red objects look similar"], colour,
                ))
        out.sort(key=lambda c: c.confidence, reverse=True)
        return out[:10]
