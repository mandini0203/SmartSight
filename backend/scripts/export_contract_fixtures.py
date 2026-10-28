"""Record real backend responses as JSON fixtures for the Flutter contract tests.

Run from backend/:  python scripts/export_contract_fixtures.py
Writes to ../frontend/test/fixtures/. The responses come from actual
inference on the Ultralytics sample images, so the Dart parsers are tested
against the real API contract rather than hand-written JSON.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

os.environ.setdefault("YOLO_AUTOINSTALL", "False")
os.environ.setdefault("YOLO_OFFLINE", "True")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from fastapi.testclient import TestClient  # noqa: E402
from ultralytics.utils import ASSETS  # noqa: E402

from app.config import Settings  # noqa: E402
from app.main import create_app  # noqa: E402

OUT = ROOT.parent / "frontend" / "test" / "fixtures"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    bus = (Path(ASSETS) / "bus.jpg").read_bytes()
    zidane = (Path(ASSETS) / "zidane.jpg").read_bytes()
    img = lambda b: {"image": ("frame.jpg", b, "image/jpeg")}  # noqa: E731

    with TestClient(create_app(Settings(warmup_on_startup=False, log_level="WARNING"))) as c:
        fixtures = {
            "status": c.get("/api/v1/status"),
            "classes": c.get("/api/v1/detection/classes"),
            "detection_bus": c.post("/api/v1/detection", files=img(bus), data={"frame_id": "f1"}),
            "scan_describe_bus": c.post("/api/v1/scan", files=img(bus), data={"task": "describe_surroundings"}),
            "scan_find_exit_bus": c.post("/api/v1/scan", files=img(bus), data={"task": "find_exit"}),
            "signs_bus": c.post("/api/v1/signs/detect", files=img(bus)),
            "colour_bus": c.post("/api/v1/colour/identify", files=img(bus),
                                 data={"point_x": "0.5", "point_y": "0.45", "normalised": "true"}),
            "intent_find_phone": c.post("/api/v1/intent/resolve", json={"text": "where is my phone"}),
            "intent_clarify": c.post("/api/v1/intent/resolve", json={"text": "find"}),
            "intent_keys": c.post("/api/v1/intent/resolve", json={"text": "find my keys"}),
            "items_match_found": c.post(
                "/api/v1/items/match",
                files=[("image", ("s.jpg", zidane, "image/jpeg")), ("references", ("r.jpg", zidane, "image/jpeg"))],
                data={"item_label": "person", "item_name": "test"},
            ),
            "items_check_reference": c.post("/api/v1/items/check-reference", files=img(zidane),
                                            data={"item_label": "person"}),
            "error_invalid_image": c.post("/api/v1/detection", files={"image": ("x.jpg", b"nope", "image/jpeg")}),
            "error_unsupported_class": c.post(
                "/api/v1/items/match",
                files=[("image", ("s.jpg", bus, "image/jpeg")), ("references", ("r.jpg", bus, "image/jpeg"))],
                data={"item_label": "keys"},
            ),
        }
        # Context fixture with a seat scenario (hand-written inputs, real reasoner output).
        fixtures["context_seats"] = c.post("/api/v1/context/analyse", json={
            "frame": {"width": 1000, "height": 800}, "task": "find_seat",
            "detections": [
                {"label": "chair", "confidence": 0.9, "bbox": {"x1": 100, "y1": 400, "x2": 300, "y2": 750}},
                {"label": "person", "confidence": 0.9, "bbox": {"x1": 110, "y1": 200, "x2": 290, "y2": 720}},
                {"label": "chair", "confidence": 0.85, "bbox": {"x1": 650, "y1": 400, "x2": 850, "y2": 750}},
            ],
        })

    for name, resp in fixtures.items():
        (OUT / f"{name}.json").write_text(
            json.dumps({"status_code": resp.status_code, "body": resp.json()}, indent=1), encoding="utf-8"
        )
        print(f"{name}: {resp.status_code}")


if __name__ == "__main__":
    main()
