"""Rule-based context reasoner via POST /api/v1/context/analyse.

Detections here are hand-written *test inputs* to exercise specific rules;
they are not presented as model output.
"""

FRAME = {"width": 1000, "height": 800}


def det(label, x1, y1, x2, y2, conf=0.9, id=None):
    d = {"label": label, "confidence": conf, "bbox": {"x1": x1, "y1": y1, "x2": x2, "y2": y2}}
    if id is not None:
        d["id"] = id
    return d


def analyse(client, detections, task="describe_surroundings", target=None):
    body = {"frame": FRAME, "detections": detections, "task": task}
    if target:
        body["target_label"] = target
    r = client.post("/api/v1/context/analyse", json=body)
    assert r.status_code == 200, r.text
    return r.json()


def seat(body, label="chair"):
    return next(s for s in body["seats"] if s["label"] == label)


def test_empty_chair_is_only_potentially_unoccupied(client):
    body = analyse(client, [det("chair", 600, 400, 800, 700)], "find_seat")
    s = seat(body)
    assert s["status"] == "POTENTIALLY_UNOCCUPIED"
    assert s["confidence"] < 0.9
    assert any("cannot be ruled out" in e for e in s["evidence"])
    assert "may be free" in body["guidance"]["message"]
    assert "right" in body["guidance"]["message"]


def test_person_sitting_on_chair_is_likely_occupied(client):
    body = analyse(client, [det("chair", 400, 400, 600, 750), det("person", 410, 200, 590, 720)], "find_seat")
    assert seat(body)["status"] == "LIKELY_OCCUPIED"
    assert "occupied" in body["guidance"]["message"]


def test_person_partly_overlapping_is_uncertain(client):
    body = analyse(client, [det("chair", 400, 400, 600, 750), det("person", 560, 100, 760, 760)], "find_seat")
    assert seat(body)["status"] == "UNCERTAIN"


def test_bag_on_chair_is_uncertain(client):
    body = analyse(client, [det("chair", 400, 400, 600, 750), det("backpack", 450, 420, 550, 520)], "find_seat")
    s = seat(body)
    assert s["status"] == "UNCERTAIN"
    assert any("backpack" in e for e in s["evidence"])


def test_low_confidence_chair_is_uncertain(client):
    body = analyse(client, [det("chair", 400, 400, 600, 750, conf=0.4)], "find_seat")
    assert seat(body)["status"] == "UNCERTAIN"


def test_free_seat_ranked_before_occupied(client):
    body = analyse(client, [
        det("chair", 100, 400, 300, 750, id=0), det("person", 110, 200, 290, 720, id=1),
        det("chair", 650, 400, 850, 750, id=2),
    ], "find_seat")
    assert body["seats"][0]["detection_id"] == 2
    assert body["guidance"]["target_ids"] == [2]


def test_partially_used_couch_is_uncertain(client):
    body = analyse(client, [det("couch", 100, 400, 900, 750), det("person", 120, 250, 380, 740)], "find_seat")
    assert seat(body, "couch")["status"] == "UNCERTAIN"


def test_no_seats(client):
    body = analyse(client, [det("person", 100, 100, 300, 700)], "find_seat")
    assert body["seats"] == []
    assert "can't see" in body["guidance"]["message"]


def test_cup_on_table_relationship_with_evidence(client):
    body = analyse(client, [det("dining table", 200, 400, 800, 750, id=0), det("cup", 450, 340, 520, 430, id=1)])
    rel = next(r for r in body["relationships"] if r["type"] == "on_top_of")
    assert rel["subject_label"] == "cup" and rel["object_label"] == "dining table"
    assert 0 < rel["confidence"] < 1
    assert rel["evidence"] and any("candidate" in e for e in rel["evidence"])


def test_no_on_top_relationship_when_far_apart(client):
    body = analyse(client, [det("dining table", 600, 400, 950, 750), det("cup", 50, 100, 100, 160)])
    assert not [r for r in body["relationships"] if r["type"] == "on_top_of"]


def test_find_object_reports_position_and_surface(client):
    body = analyse(client, [det("dining table", 200, 400, 800, 750, id=0), det("cell phone", 250, 360, 330, 420, id=1)],
                   "find_object", "cell phone")
    g = body["guidance"]
    assert g["target_ids"] == [1]
    assert "Cell phone" in g["message"] and "dining table" in g["message"]
    assert body["relevant_object_ids"] == [1]


def test_find_object_not_visible(client):
    body = analyse(client, [det("chair", 100, 100, 200, 300)], "find_object", "cell phone")
    assert "can't see a cell phone" in body["guidance"]["message"]


def test_find_unsupported_object(client):
    body = analyse(client, [], "find_object", "keys")
    assert "cannot recognise" in body["guidance"]["message"]
    assert body["guidance"]["confidence"] == 0


def test_find_exit_uses_sign_candidates(client):
    body = analyse(client, [det("door", 100, 100, 300, 700, conf=0.5), det("exit sign", 700, 50, 800, 100, conf=0.6)],
                   "find_exit")
    assert body["guidance"]["message"].startswith("An exit sign may be")
    assert "confirm" in body["guidance"]["message"]


def test_describe_counts_objects(client):
    body = analyse(client, [det("person", 100, 100, 300, 700), det("person", 500, 100, 700, 700),
                            det("chair", 800, 400, 950, 700)])
    assert "2 people" in body["guidance"]["message"] and "a chair" in body["guidance"]["message"]


def test_describe_nothing(client):
    body = analyse(client, [])
    assert "did not detect" in body["guidance"]["message"]


def test_response_declares_rule_based_and_disclaimer(client):
    body = analyse(client, [])
    assert body["reasoner"]["is_trained_model"] is False
    assert "mobility aid" in body["disclaimer"]


def test_distance_estimate_included_with_range(client):
    body = analyse(client, [det("person", 400, 100, 500, 600)])
    d = body["objects"][0]["distance"]
    assert d and d["low_metres"] < d["metres"] < d["high_metres"]
    assert d["method"] == "known_size_pinhole"


def test_truncated_object_gets_no_distance(client):
    body = analyse(client, [det("person", 400, 0, 500, 600)])
    assert body["objects"][0]["distance"] is None


def test_invalid_bbox_rejected(client):
    r = client.post("/api/v1/context/analyse", json={
        "frame": FRAME, "detections": [det("chair", 500, 400, 400, 700)]})
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "validation_error"


def test_invalid_task_rejected(client):
    r = client.post("/api/v1/context/analyse", json={"frame": FRAME, "detections": [], "task": "fly"})
    assert r.status_code == 422
