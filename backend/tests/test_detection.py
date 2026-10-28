import pytest


def post_image(client, data: bytes, name="img.jpg", ctype="image/jpeg", **form):
    return client.post("/api/v1/detection", files={"image": (name, data, ctype)}, data=form)


def test_real_yolov8_inference_on_sample_image(client, bus_jpg):
    r = post_image(client, bus_jpg)
    assert r.status_code == 200, r.text
    body = r.json()
    labels = [d["label"] for d in body["detections"]]
    assert "bus" in labels
    assert labels.count("person") >= 3
    assert body["frame"] == {"width": 810, "height": 1080, "frame_id": None, "captured_at": None}
    assert body["model"]["model_file"] == "yolov8n.pt"
    assert body["processing"]["total_ms"] > 0
    for d in body["detections"]:
        b, n = d["bbox"], d["bbox_normalised"]
        assert 0 <= b["x1"] < b["x2"] <= 810 and 0 <= b["y1"] < b["y2"] <= 1080
        assert 0 <= n["x1"] < n["x2"] <= 1 and 0 <= n["y1"] < n["y2"] <= 1
        assert 0 < d["confidence"] <= 1
        assert d["position"]["clock_label"].endswith("o'clock")


def test_detections_sorted_and_threshold_applied(client, bus_jpg):
    body = post_image(client, bus_jpg, confidence="0.8").json()
    confs = [d["confidence"] for d in body["detections"]]
    assert confs == sorted(confs, reverse=True)
    assert all(c >= 0.8 for c in confs)
    assert body["processing"]["confidence_threshold"] == 0.8


def test_blank_image_returns_no_fabricated_detections(client, solid_image):
    r = post_image(client, solid_image((128, 128, 128)), "blank.png", "image/png")
    assert r.status_code == 200
    assert r.json()["detections"] == []


def test_class_filter(client, bus_jpg):
    body = post_image(client, bus_jpg, classes="person").json()
    assert body["detections"] and all(d["label"] == "person" for d in body["detections"])


def test_unsupported_class_filter_rejected(client, bus_jpg):
    r = post_image(client, bus_jpg, classes="keys")
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "unsupported_class"


def test_optional_fields_can_be_disabled(client, bus_jpg):
    body = post_image(client, bus_jpg, include_position="false", include_distance="false").json()
    assert all(d["position"] is None and d["distance"] is None for d in body["detections"])


def test_frame_id_round_trip(client, bus_jpg):
    assert post_image(client, bus_jpg, frame_id="f-42").json()["frame"]["frame_id"] == "f-42"


def test_supported_classes(client):
    body = client.get("/api/v1/detection/classes").json()
    assert len(body["classes"]) == 80
    assert "cell phone" in body["classes"] and "door" not in body["classes"]


@pytest.mark.parametrize(
    "data,ctype,status,code",
    [
        (b"not an image", "image/jpeg", 422, "invalid_image"),
        (b"", "image/jpeg", 422, "invalid_image"),
        (b"GIF89a....", "image/gif", 415, "unsupported_media_type"),
    ],
)
def test_invalid_uploads(client, data, ctype, status, code):
    r = post_image(client, data, ctype=ctype)
    assert r.status_code == status
    body = r.json()
    assert body["error"]["code"] == code
    assert body["request_id"]


def test_missing_image_field(client):
    r = client.post("/api/v1/detection", data={"confidence": "0.5"})
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "validation_error"


def test_out_of_range_confidence(client, bus_jpg):
    assert post_image(client, bus_jpg, confidence="1.5").status_code == 422


def test_tiny_image_rejected(client, solid_image):
    r = post_image(client, solid_image((0, 0, 0), size=(10, 10)), "t.png", "image/png")
    assert r.status_code == 422


def test_upload_size_limit(make_client, bus_jpg):
    c = make_client(max_upload_bytes=2048)
    r = post_image(c, bus_jpg)
    assert r.status_code == 413
    assert r.json()["error"]["code"] == "payload_too_large"


def test_busy_server_rejects_instead_of_queueing():
    import asyncio
    import time

    from app.errors import ServiceUnavailableError
    from app.services.registry import InferenceGate

    async def scenario():
        gate = InferenceGate(max_concurrent=1, max_waiting=1)
        first = asyncio.create_task(gate.run(time.sleep, 0.3))
        await asyncio.sleep(0.05)  # first request is now holding the only slot
        with pytest.raises(ServiceUnavailableError):
            await gate.run(lambda: 1)
        await first

    asyncio.run(scenario())


def test_timeout_maps_to_504():
    import asyncio
    import time

    from app.errors import InferenceTimeoutError
    from app.services.registry import InferenceGate

    gate = InferenceGate(timeout_s=0.05)
    with pytest.raises(InferenceTimeoutError):
        asyncio.run(gate.run(time.sleep, 0.3))
