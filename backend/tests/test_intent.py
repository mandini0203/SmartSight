import pytest

CASES = [
    ("Where's my phone?", "RESOLVED", "find_object", "cell phone"),
    ("find my phone", "RESOLVED", "find_object", "cell phone"),
    ("can you help me find my mobile please", "RESOLVED", "find_object", "cell phone"),
    ("I lost my backpack", "RESOLVED", "find_object", "backpack"),
    ("where is the water bottle", "RESOLVED", "find_object", "bottle"),
    ("find the exit", "RESOLVED", "find_exit", None),
    ("How do I get out of here", "RESOLVED", "find_exit", None),
    ("where is the door", "RESOLVED", "find_exit", None),
    ("find the exit sign", "RESOLVED", "find_exit", None),
    ("find a place to sit", "RESOLVED", "find_seat", None),
    ("I want to sit down", "RESOLVED", "find_seat", None),
    ("is there a free chair", "RESOLVED", "find_seat", "chair"),
    ("what colour is this", "RESOLVED", "identify_colour", None),
    ("what color is my bag", "RESOLVED", "identify_colour", "handbag"),
    ("describe my surroundings", "RESOLVED", "describe_surroundings", None),
    ("what's in front of me", "RESOLVED", "describe_surroundings", None),
    ("what can you see", "RESOLVED", "describe_surroundings", None),
    ("find my keys", "UNSUPPORTED", "find_object", None),
    ("find", "NEEDS_CLARIFICATION", "find_object", None),
    ("blah blah", "UNSUPPORTED", None, None),
    ("go home", "UNSUPPORTED", None, None),
    ("pause scanning", "UNSUPPORTED", None, None),
]


@pytest.mark.parametrize("text,status,intent,label", CASES)
def test_rule_based_intents(client, text, status, intent, label):
    r = client.post("/api/v1/intent/resolve", json={"text": text})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["status"] == status, body
    assert body["intent"] == intent, body
    assert body["slots"]["target_label"] == label
    assert body["resolver"]["is_trained_model"] is False
    assert body["message"]


def test_personal_flag(client):
    assert client.post("/api/v1/intent/resolve", json={"text": "find my phone"}).json()["slots"]["personal"] is True
    assert client.post("/api/v1/intent/resolve", json={"text": "find a phone"}).json()["slots"]["personal"] is False


def test_ambiguous_request_asks_for_clarification(client):
    body = client.post("/api/v1/intent/resolve", json={"text": "describe the colour"}).json()
    assert body["status"] == "NEEDS_CLARIFICATION"
    assert body["clarification_question"]
    assert len(body["alternatives"]) >= 2


def test_app_commands_are_left_to_the_phone(client):
    body = client.post("/api/v1/intent/resolve", json={"text": "open colour finder"}).json()
    assert body["matched_rules"] == ["app_command"]


def test_evidence_of_matched_rules(client):
    body = client.post("/api/v1/intent/resolve", json={"text": "where is my phone"}).json()
    assert "find_verb" in body["matched_rules"] and "object_slot_present" in body["matched_rules"]


@pytest.mark.parametrize("payload", [{"text": ""}, {"text": "   "}, {"text": "x" * 501}, {}])
def test_invalid_requests(client, payload):
    r = client.post("/api/v1/intent/resolve", json=payload)
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "validation_error"


def test_validation_error_does_not_echo_input(client):
    secret = "my medical appointment " * 30
    r = client.post("/api/v1/intent/resolve", json={"text": secret})
    assert "medical" not in r.text
