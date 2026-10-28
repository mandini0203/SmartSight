"""Personal-item matching: is this detected object *my* registered item?

YOLOv8 only says "a cell phone". To decide whether it is the user's phone, the
candidate crop is compared with the user's reference photos using:

  * ``embedding``  - cosine similarity of ImageNet-pretrained MobileNetV3-Small
                     global features (torchvision weights, not fine-tuned);
  * ``colour``     - HSV histogram correlation (captures case colour, stickers);
  * ``keypoints``  - ORB keypoint matches with Lowe ratio test (captures
                     distinctive texture/printing).

The weighted combination and the decision thresholds are *uncalibrated
defaults*. Use ``scripts/evaluate_item_matching.py`` with your own photo pairs
to measure and tune them. Two items of the same model and colour can be
indistinguishable to this method.
"""

from __future__ import annotations

import logging
import threading

import cv2
import numpy as np

from app.schemas.common import ComponentInfo
from app.services.interfaces import PersonalItemMatcher

logger = logging.getLogger("smartsight.items")

EMB_WEIGHT, COLOUR_WEIGHT, KP_WEIGHT = 0.55, 0.25, 0.20
EMB_FLOOR = 0.45  # cosine similarity typical of unrelated objects of the same class


def colour_similarity(a: np.ndarray, b: np.ndarray) -> float:
    def hist(img: np.ndarray) -> np.ndarray:
        hsv = cv2.cvtColor(cv2.resize(img, (128, 128)), cv2.COLOR_RGB2HSV)
        h = cv2.calcHist([hsv], [0, 1], None, [18, 8], [0, 180, 0, 256])
        return cv2.normalize(h, h).flatten()
    c = cv2.compareHist(hist(a), hist(b), cv2.HISTCMP_CORREL)
    return float(np.clip(c, 0.0, 1.0))


_orb = cv2.ORB_create(nfeatures=500)
_bf = cv2.BFMatcher(cv2.NORM_HAMMING)


def keypoint_similarity(a: np.ndarray, b: np.ndarray) -> float:
    def prep(img: np.ndarray) -> np.ndarray:
        g = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY)
        s = 320 / max(g.shape)
        return cv2.resize(g, (max(1, int(g.shape[1] * s)), max(1, int(g.shape[0] * s))))
    ka, da = _orb.detectAndCompute(prep(a), None)
    kb, db = _orb.detectAndCompute(prep(b), None)
    if da is None or db is None or len(ka) < 8 or len(kb) < 8:
        return 0.0
    pairs = _bf.knnMatch(da, db, k=2)
    good = [p[0] for p in pairs if len(p) == 2 and p[0].distance < 0.75 * p[1].distance]
    # 40 good matches (or 25 % of the smaller keypoint set) counts as a strong match.
    target = min(40.0, 0.25 * min(len(ka), len(kb)))
    return float(np.clip(len(good) / max(target, 8.0), 0.0, 1.0))


class ClassicalItemMatcher(PersonalItemMatcher):
    """Colour histogram + ORB keypoints. No model download required."""

    @property
    def info(self) -> ComponentInfo:
        return ComponentInfo(
            name="orb_colour_matcher",
            version="1.0",
            is_trained_model=False,
            description="HSV colour histogram correlation plus ORB keypoint matching (classical CV).",
        )

    def is_ready(self) -> bool:
        return True

    def similarity(self, candidate, references):
        best, best_parts = 0.0, {}
        for ref in references:
            c = colour_similarity(candidate, ref)
            k = keypoint_similarity(candidate, ref)
            s = 0.6 * c + 0.4 * k
            if s > best:
                best, best_parts = s, {"colour": round(c, 3), "keypoints": round(k, 3)}
        return round(best, 3), best_parts


class EmbeddingItemMatcher(PersonalItemMatcher):
    """Pretrained CNN embeddings combined with the classical cues."""

    def __init__(self, torch_home: str | None = None) -> None:
        self.torch_home = torch_home
        self._model = None
        self._transform = None
        self._lock = threading.Lock()
        self.load_error: str | None = None

    def load(self) -> None:
        try:
            import torch
            from torchvision.models import MobileNet_V3_Small_Weights, mobilenet_v3_small

            if self.torch_home:
                torch.hub.set_dir(self.torch_home)  # weights live in backend/models/torch/hub
            weights = MobileNet_V3_Small_Weights.IMAGENET1K_V1
            model = mobilenet_v3_small(weights=weights)
            model.classifier = torch.nn.Identity()  # 576-d pooled features
            model.eval()
            self._transform = weights.transforms()
            self._model = model
            self._torch = torch
            logger.info("Loaded MobileNetV3-Small embedding model")
        except Exception as exc:  # pragma: no cover - environment dependent
            self.load_error = f"Embedding model unavailable: {exc}"
            logger.error(self.load_error)

    @property
    def info(self) -> ComponentInfo:
        return ComponentInfo(
            name="embedding_matcher",
            version="1.0",
            is_trained_model=True,
            description=(
                "ImageNet-pretrained MobileNetV3-Small features (not fine-tuned) + colour histogram "
                "+ ORB keypoints. Thresholds are uncalibrated defaults."
            ),
        )

    def is_ready(self) -> bool:
        return self._model is not None

    def _embed(self, images: list[np.ndarray]) -> np.ndarray:
        from PIL import Image

        torch = self._torch
        batch = torch.stack([self._transform(Image.fromarray(img)) for img in images])
        with self._lock, torch.inference_mode():
            feats = self._model(batch).cpu().numpy()
        norms = np.linalg.norm(feats, axis=1, keepdims=True)
        return feats / np.maximum(norms, 1e-8)

    def similarity(self, candidate, references):
        if self._model is None:
            raise RuntimeError(self.load_error or "Embedding model not loaded")
        embs = self._embed([candidate, *references])
        cosines = embs[1:] @ embs[0]
        best, best_parts = 0.0, {}
        for ref, cos in zip(references, cosines):
            emb_score = float(np.clip((cos - EMB_FLOOR) / (1 - EMB_FLOOR), 0.0, 1.0))
            c = colour_similarity(candidate, ref)
            k = keypoint_similarity(candidate, ref)
            s = EMB_WEIGHT * emb_score + COLOUR_WEIGHT * c + KP_WEIGHT * k
            if s > best:
                best = s
                best_parts = {"embedding_cosine": round(float(cos), 3), "embedding": round(emb_score, 3),
                              "colour": round(c, 3), "keypoints": round(k, 3)}
        return round(best, 3), best_parts
