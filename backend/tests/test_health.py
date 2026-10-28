def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert "version" in body
    assert r.headers["x-request-id"]


def test_status_reports_real_components(client):
    r = client.get("/api/v1/status")
    assert r.status_code == 200
    body = r.json()
    assert body["detector"]["ready"] is True
    assert body["detector_model"]["model_file"] == "yolov8n.pt"
    assert body["detector_model"]["num_classes"] == 80
    # Rule-based services must never present themselves as trained models.
    assert body["context"]["component"]["is_trained_model"] is False
    assert body["intent"]["component"]["is_trained_model"] is False
    assert body["colour"]["component"]["is_trained_model"] is False


def test_unknown_route_uses_error_shape(client):
    r = client.get("/api/v1/does-not-exist")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "not_found"


def test_request_id_is_echoed_when_safe(client):
    r = client.get("/health", headers={"x-request-id": "abc123"})
    assert r.headers["x-request-id"] == "abc123"
    r = client.get("/health", headers={"x-request-id": "bad id\nwith newline"})
    assert r.headers["x-request-id"] != "bad id\nwith newline"


def test_openapi_documents_all_endpoints(client):
    paths = client.get("/openapi.json").json()["paths"]
    for p in ["/health", "/api/v1/status", "/api/v1/detection", "/api/v1/detection/classes",
              "/api/v1/context/analyse", "/api/v1/scan", "/api/v1/intent/resolve", "/api/v1/items/match",
              "/api/v1/items/check-reference", "/api/v1/colour/identify", "/api/v1/signs/detect",
              "/api/v1/auth/register", "/api/v1/auth/login", "/api/v1/auth/google", "/api/v1/auth/refresh",
              "/api/v1/me", "/api/v1/me/items"]:
        assert p in paths, p
