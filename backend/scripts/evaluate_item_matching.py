"""Calibrate / evaluate personal-item matching on your own photos.

Folder layout (at least two items, at least two photos each):

    items/
      blue_phone/   1.jpg 2.jpg 3.jpg ...
      black_phone/  1.jpg 2.jpg ...

Usage: python scripts/evaluate_item_matching.py items/ --label "cell phone" [--matcher embedding|orb]

For every photo, the remaining photos of the same item are the references
("genuine" pair) and each other item's photos are references ("impostor"
pair). The script reports both score distributions and the false-match and
false-reject rates at the configured thresholds. Use it to choose
SMARTSIGHT_ITEM_MATCH_THRESHOLD; no such data was available when the defaults were set.
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
from pathlib import Path

os.environ.setdefault("YOLO_AUTOINSTALL", "False")
os.environ.setdefault("YOLO_OFFLINE", "True")
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import numpy as np  # noqa: E402
from PIL import Image, ImageOps  # noqa: E402

from app.config import Settings  # noqa: E402
from app.services.detection.yolo_detector import YoloV8Detector  # noqa: E402
from app.services.items.matcher import ClassicalItemMatcher, EmbeddingItemMatcher  # noqa: E402
from app.utils.image_io import crop  # noqa: E402


def load(p: Path) -> np.ndarray:
    return np.asarray(ImageOps.exif_transpose(Image.open(p)).convert("RGB"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("folder", type=Path)
    ap.add_argument("--label", required=True)
    ap.add_argument("--matcher", choices=["embedding", "orb"], default="embedding")
    args = ap.parse_args()
    s = Settings()

    det = YoloV8Detector(s.model_path, confidence=0.25, iou=s.detection_iou, image_size=s.detection_image_size,
                         max_results=10, device=s.inference_device)
    det.load()
    if args.matcher == "embedding":
        matcher = EmbeddingItemMatcher(str(s.model_path.parent / "torch" / "hub"))
        matcher.load()
    else:
        matcher = ClassicalItemMatcher()

    def item_crop(img: np.ndarray) -> np.ndarray:
        out = det.detect(img, classes=[args.label])
        if not out.detections:
            return img
        d = max(out.detections, key=lambda d: (d.x2 - d.x1) * (d.y2 - d.y1))
        return crop(img, d.x1, d.y1, d.x2, d.y2, 0.08)

    items = {d.name: [item_crop(load(p)) for p in sorted(d.iterdir()) if p.suffix.lower() in {".jpg", ".jpeg", ".png"}]
             for d in sorted(args.folder.iterdir()) if d.is_dir()}
    items = {k: v for k, v in items.items() if len(v) >= 2}
    if len(items) < 2:
        print("Need at least two item folders with two or more photos each.")
        return 1

    genuine, impostor = [], []
    for name, photos in items.items():
        for i, probe in enumerate(photos):
            refs = photos[:i] + photos[i + 1:]
            genuine.append(matcher.similarity(probe, refs)[0])
            for other, ophotos in items.items():
                if other != name:
                    impostor.append(matcher.similarity(probe, ophotos)[0])

    def rates(t: float) -> dict:
        return {"threshold": t,
                "false_reject_rate": round(sum(g < t for g in genuine) / len(genuine), 3),
                "false_match_rate": round(sum(i >= t for i in impostor) / len(impostor), 3)}

    report = {
        "matcher": matcher.info.name,
        "genuine": {"n": len(genuine), "median": round(statistics.median(genuine), 3), "min": round(min(genuine), 3)},
        "impostor": {"n": len(impostor), "median": round(statistics.median(impostor), 3),
                     "max": round(max(impostor), 3)},
        "at_configured_match_threshold": rates(s.item_match_threshold),
        "at_configured_possible_threshold": rates(s.item_possible_match_threshold),
        "sweep": [rates(round(t, 2)) for t in np.arange(0.4, 0.96, 0.05)],
    }
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
