import numpy as np
from PIL import Image

from app.services.signs.detector import HeuristicExitSignDetector


def test_item_match_same_photo_is_found(client, zidane_jpg):
    r = client.post(
        "/api/v1/items/match",
        files=[("image", ("s.jpg", zidane_jpg, "image/jpeg")), ("references", ("r.jpg", zidane_jpg, "image/jpeg"))],
        data={"item_label": "person", "item_name": "test subject"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["status"] == "FOUND"
    assert body["best"]["decision"] == "MATCH"
    assert set(body["thresholds"]) == {"match", "possible_match"}
    assert "test subject" in body["message"]


def test_item_match_different_photo_is_not_found(client, zidane_jpg, bus_jpg):
    r = client.post(
        "/api/v1/items/match",
        files=[("image", ("s.jpg", zidane_jpg, "image/jpeg")), ("references", ("r.jpg", bus_jpg, "image/jpeg"))],
        data={"item_label": "person"},
    )
    body = r.json()
    assert body["status"] in {"NOT_FOUND", "POSSIBLY_FOUND"}
    assert body["best"]["similarity"] < body["thresholds"]["match"]


def test_item_match_no_candidates(client, solid_image, bus_jpg):
    r = client.post(
        "/api/v1/items/match",
        files=[("image", ("s.png", solid_image((90, 90, 90)), "image/png")),
               ("references", ("r.jpg", bus_jpg, "image/jpeg"))],
        data={"item_label": "cell phone"},
    )
    assert r.json()["status"] == "NO_CANDIDATES"


def test_item_match_rejects_unsupported_label(client, bus_jpg):
    r = client.post(
        "/api/v1/items/match",
        files=[("image", ("s.jpg", bus_jpg, "image/jpeg")), ("references", ("r.jpg", bus_jpg, "image/jpeg"))],
        data={"item_label": "keys"},
    )
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "unsupported_class"


def test_item_match_reference_count_limit(client, bus_jpg):
    files = [("image", ("s.jpg", bus_jpg, "image/jpeg"))] + [
        ("references", (f"r{i}.jpg", bus_jpg, "image/jpeg")) for i in range(6)]
    r = client.post("/api/v1/items/match", files=files, data={"item_label": "person"})
    assert r.status_code == 422


def test_check_reference(client, zidane_jpg, solid_image):
    ok = client.post("/api/v1/items/check-reference", files={"image": ("r.jpg", zidane_jpg, "image/jpeg")},
                     data={"item_label": "person"}).json()
    assert ok["detected"] is True
    bad = client.post("/api/v1/items/check-reference", files={"image": ("r.png", solid_image((90, 90, 90)), "image/png")},
                      data={"item_label": "cell phone"}).json()
    assert bad["accepted"] is False and bad["issues"]


def test_signs_endpoint_structure(client, bus_jpg):
    r = client.post("/api/v1/signs/detect", files={"image": ("b.jpg", bus_jpg, "image/jpeg")})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["message"]
    for c in body["candidates"]:
        assert c["kind"] in {"exit_sign", "door"}
        assert c["evidence"]
        assert 0 <= c["confidence"] <= 1


def test_bus_destination_display_is_only_a_weak_exit_candidate(client, bus_jpg):
    """Known false positive of YOLO-World on bus.jpg: colour verification must keep it weak."""
    body = client.post("/api/v1/signs/detect", files={"image": ("b.jpg", bus_jpg, "image/jpeg")}).json()
    assert all(c["confidence"] < 0.35 for c in body["candidates"] if c["kind"] == "exit_sign")


def test_heuristic_exit_sign_on_synthetic_panel(exit_sign_png):
    import io

    rgb = np.asarray(Image.open(io.BytesIO(exit_sign_png)).convert("RGB"))
    cands = HeuristicExitSignDetector().detect(rgb)
    assert cands, "green exit-sign panel should be found"
    x1, y1, x2, y2 = cands[0].box
    assert 360 <= x1 <= 400 and 40 <= y1 <= 80 and 540 <= x2 <= 580
    assert cands[0].sign_colour == "green"


def test_heuristic_ignores_plain_wall(solid_image):
    import io

    rgb = np.asarray(Image.open(io.BytesIO(solid_image((150, 150, 145)))).convert("RGB"))
    assert HeuristicExitSignDetector().detect(rgb) == []


def test_scan_combines_detection_and_context(client, bus_jpg):
    r = client.post("/api/v1/scan", files={"image": ("b.jpg", bus_jpg, "image/jpeg")},
                    data={"task": "describe_surroundings", "frame_id": "7"})
    assert r.status_code == 200
    body = r.json()
    assert body["detection"]["frame"]["frame_id"] == "7"
    assert body["signs"] is None
    assert "bus" in body["context"]["guidance"]["message"]
    assert len(body["context"]["objects"]) == len(body["detection"]["detections"])


def test_scan_find_exit_runs_sign_detector(client, bus_jpg):
    body = client.post("/api/v1/scan", files={"image": ("b.jpg", bus_jpg, "image/jpeg")},
                       data={"task": "find_exit"}).json()
    assert body["signs"] is not None
    assert body["context"]["task"] == "find_exit"


def test_scan_find_object(client, bus_jpg):
    body = client.post("/api/v1/scan", files={"image": ("b.jpg", bus_jpg, "image/jpeg")},
                       data={"task": "find_object", "target_label": "bus"}).json()
    assert body["context"]["guidance"]["message"].startswith("Bus")
