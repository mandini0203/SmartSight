"""Accounts: registration, sign-in, Google, token rotation, profile and items."""

from __future__ import annotations

import itertools

import pytest

from app.services.accounts.google import GoogleIdentity, GoogleTokenError

_seq = itertools.count(1)


def profile(**overrides) -> dict:
    """A valid registration body with a unique email and NIC."""
    n = next(_seq)
    body = {
        "email": f"user{n}@example.com",
        "password": "correct horse 9",
        "first_name": "Nimal",
        "last_name": "Perera",
        "nic": f"1998123{n:05d}",  # day 123 -> 2 May 1998, male
        "address_line1": "12 Galle Road",
        "address_line2": "Bambalapitiya",
        "address_line3": "Colombo",
        "postal_code": "00400",
        "mobile": "077 123 4567",
        "whatsapp_same_as_mobile": True,
        "eyesight": "severe",
    }
    body.update(overrides)
    return body


def register(client, **overrides):
    return client.post("/api/v1/auth/register", json=profile(**overrides))


def auth(tokens: dict) -> dict:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


# ------------------------------------------------------------ registration
def test_register_derives_birthday_gender_and_age_from_nic(client):
    r = register(client)
    assert r.status_code == 201, r.text
    body = r.json()
    user = body["user"]
    assert body["is_new_user"] is True and body["token_type"] == "bearer"
    assert user["birthday"] == "1998-05-02"
    assert user["gender"] == "male"
    assert isinstance(user["age"], int) and user["age"] >= 27
    assert user["mobile"] == "+94771234567"
    assert user["whatsapp"] == "+94771234567"  # copied because whatsapp_same_as_mobile
    assert user["profile_complete"] is True and user["has_password"] is True
    assert "correct horse" not in r.text and "password_hash" not in r.text


def test_register_female_old_nic(client):
    r = register(client, nic=f"98{623 + 0}{next(_seq):04d}V")
    assert r.status_code == 201, r.text
    assert r.json()["user"]["gender"] == "female"
    assert r.json()["user"]["birthday"] == "1998-05-02"


@pytest.mark.parametrize("overrides, fragment", [
    ({"nic": "12345"}, "valid format"),
    ({"birthday": "1990-01-01"}, "does not match the NIC"),
    ({"gender": "female"}, "does not match the NIC"),
    ({"postal_code": "12"}, "5-digit postal code"),
    ({"mobile": "12"}, "phone number"),
    ({"password": "short1"}, "at least 8 characters"),
    ({"password": "onlyletters"}, "a letter and a number"),
    ({"first_name": "N1mal"}, "letters"),
    ({"email": "not-an-email"}, "valid email"),
    ({"bmi": 5}, "BMI"),
    ({"address_line1": "   "}, "first line"),
])
def test_register_validation_messages(client, overrides, fragment):
    r = register(client, **overrides)
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "validation_error"
    assert fragment in r.json()["error"]["message"]


def test_gender_other_is_allowed_with_any_nic(client):
    r = register(client, gender="prefer_not_to_say")
    assert r.status_code == 201
    assert r.json()["user"]["gender"] == "prefer_not_to_say"


def test_duplicate_email_and_nic_are_rejected(client):
    first = profile()
    assert client.post("/api/v1/auth/register", json=first).status_code == 201
    r = register(client, email=first["email"].upper())
    assert r.status_code == 409 and r.json()["error"]["code"] == "email_in_use"
    r = register(client, nic=first["nic"])
    assert r.status_code == 409 and r.json()["error"]["code"] == "nic_in_use"


# ------------------------------------------------------------------ login
def test_login_and_wrong_password(client):
    body = profile()
    client.post("/api/v1/auth/register", json=body)
    r = client.post("/api/v1/auth/login", json={"email": body["email"].upper(), "password": body["password"]})
    assert r.status_code == 200
    assert r.json()["user"]["email"] == body["email"]
    r = client.post("/api/v1/auth/login", json={"email": body["email"], "password": "wrong password 1"})
    assert r.status_code == 401 and r.json()["error"]["code"] == "invalid_credentials"
    r = client.post("/api/v1/auth/login", json={"email": "nobody@example.com", "password": "whatever 1"})
    assert r.status_code == 401 and r.json()["error"]["code"] == "invalid_credentials"


def test_login_is_throttled_after_repeated_failures(make_client):
    c = make_client(login_max_failures=3)
    body = profile()
    c.post("/api/v1/auth/register", json=body)
    wrong = {"email": body["email"], "password": "wrong password 1"}
    for _ in range(3):
        assert c.post("/api/v1/auth/login", json=wrong).status_code == 401
    r = c.post("/api/v1/auth/login", json={"email": body["email"], "password": body["password"]})
    assert r.status_code == 429
    assert r.json()["error"]["details"]["retry_after_seconds"] > 0


# --------------------------------------------------------- tokens/session
def test_profile_requires_a_valid_token(client):
    assert client.get("/api/v1/me").json()["error"]["code"] == "not_authenticated"
    r = client.get("/api/v1/me", headers={"Authorization": "Bearer nonsense"})
    assert r.status_code == 401 and r.json()["error"]["code"] == "invalid_token"


def test_refresh_rotates_and_detects_reuse(client):
    tokens = register(client).json()
    r = client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert r.status_code == 200
    rotated = r.json()
    assert rotated["refresh_token"] != tokens["refresh_token"]
    assert client.get("/api/v1/me", headers=auth(rotated)).status_code == 200

    # Re-using the old token ends every session, including the rotated one.
    r = client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert r.status_code == 401
    r = client.post("/api/v1/auth/refresh", json={"refresh_token": rotated["refresh_token"]})
    assert r.status_code == 401


def test_logout_revokes_refresh_token(client):
    tokens = register(client).json()
    assert client.post("/api/v1/auth/logout", json={"refresh_token": tokens["refresh_token"]}).status_code == 204
    r = client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert r.status_code == 401


# ---------------------------------------------------------------- profile
def test_update_profile(client):
    tokens = register(client).json()
    update = {k: v for k, v in profile().items() if k not in ("email", "password")}
    update.update(first_name="Kamala", nic=f"1985{623:03d}{next(_seq):05d}", whatsapp_same_as_mobile=False,
                  whatsapp="0711111111", bmi=22.46, eyesight="total")
    r = client.put("/api/v1/me", json=update, headers=auth(tokens))
    assert r.status_code == 200, r.text
    u = r.json()
    assert (u["first_name"], u["gender"], u["birthday"]) == ("Kamala", "female", "1985-05-02")
    assert (u["whatsapp"], u["bmi"], u["eyesight"]) == ("+94711111111", 22.5, "total")


def test_delete_account(client):
    tokens = register(client).json()
    assert client.delete("/api/v1/me", headers=auth(tokens)).status_code == 204
    assert client.get("/api/v1/me", headers=auth(tokens)).status_code == 401


# ----------------------------------------------------------------- google
class FakeGoogle:
    configured = True

    def __init__(self):
        self.identities: dict[str, GoogleIdentity] = {}

    def verify(self, token: str) -> GoogleIdentity:
        if token not in self.identities:
            raise GoogleTokenError("bad signature")
        return self.identities[token]


@pytest.fixture
def google(client):
    original = client.app.state.google_verifier
    fake = FakeGoogle()
    client.app.state.google_verifier = fake
    yield fake
    client.app.state.google_verifier = original


def test_google_sign_up_then_complete_profile_then_sign_in(client, google):
    token = "g" * 40
    google.identities[token] = GoogleIdentity(sub="google-123", email="Asha@Gmail.com".lower(), email_verified=True,
                                              given_name="Asha", family_name="Silva")
    r = client.post("/api/v1/auth/google", json={"id_token": token})
    assert r.status_code == 200, r.text
    first = r.json()
    assert first["is_new_user"] is True
    assert first["user"]["profile_complete"] is False
    assert (first["user"]["first_name"], first["user"]["has_password"], first["user"]["google_linked"]) == \
        ("Asha", False, True)

    details = {k: v for k, v in profile().items() if k not in ("email", "password")}
    details.update(first_name="Asha", last_name="Silva")
    r = client.put("/api/v1/me", json=details, headers=auth(first))
    assert r.json()["profile_complete"] is True

    again = client.post("/api/v1/auth/google", json={"id_token": token}).json()
    assert again["is_new_user"] is False and again["user"]["id"] == first["user"]["id"]

    # A Google-only account cannot sign in with a password.
    r = client.post("/api/v1/auth/login", json={"email": "asha@gmail.com", "password": "anything 1"})
    assert r.json()["error"]["code"] == "use_google_sign_in"


def test_google_does_not_take_over_password_account(client, google):
    body = profile()
    client.post("/api/v1/auth/register", json=body)
    token = "h" * 40
    google.identities[token] = GoogleIdentity(sub="google-999", email=body["email"], email_verified=True,
                                              given_name="X", family_name="Y")
    r = client.post("/api/v1/auth/google", json={"id_token": token})
    assert r.status_code == 409 and r.json()["error"]["code"] == "email_in_use"


def test_google_rejects_bad_or_unverified_tokens(client, google):
    r = client.post("/api/v1/auth/google", json={"id_token": "x" * 40})
    assert r.status_code == 401 and r.json()["error"]["code"] == "invalid_google_token"
    google.identities["u" * 40] = GoogleIdentity(sub="s", email="u@example.com", email_verified=False,
                                                 given_name="", family_name="")
    r = client.post("/api/v1/auth/google", json={"id_token": "u" * 40})
    assert r.json()["error"]["code"] == "google_email_unverified"


def test_google_not_configured(client):
    r = client.post("/api/v1/auth/google", json={"id_token": "z" * 40})
    assert r.status_code == 503 and r.json()["error"]["code"] == "service_unavailable"


# ------------------------------------------------------------------ items
def test_item_upload_list_download_delete(client, solid_image):
    tokens = register(client).json()
    h = auth(tokens)
    photo = solid_image((200, 30, 30), fmt="JPEG")
    files = [("photos", ("0.jpg", photo, "image/jpeg")), ("photos", ("1.jpg", photo, "image/jpeg"))]
    data = {"id": "abc123", "name": "My red phone", "label": "cell phone"}
    r = client.post("/api/v1/me/items", data=data, files=files, headers=h)
    assert r.status_code == 201, r.text
    assert r.json()["photo_count"] == 2

    # Retrying the same upload is harmless.
    r = client.post("/api/v1/me/items", data=data, files=files, headers=h)
    assert r.status_code == 200

    items = client.get("/api/v1/me/items", headers=h).json()
    assert [(i["id"], i["name"]) for i in items] == [("abc123", "My red phone")]

    r = client.get("/api/v1/me/items/abc123/photos/1", headers=h)
    assert r.status_code == 200 and r.content == photo
    assert client.get("/api/v1/me/items/abc123/photos/2", headers=h).status_code == 404

    # Another user cannot see the item.
    other = register(client).json()
    assert client.get("/api/v1/me/items/abc123/photos/0", headers=auth(other)).status_code == 404
    assert client.get("/api/v1/me/items", headers=auth(other)).json() == []

    assert client.delete("/api/v1/me/items/abc123", headers=h).status_code == 204
    assert client.get("/api/v1/me/items", headers=h).json() == []


def test_item_upload_validation(client, solid_image):
    h = auth(register(client).json())
    photo = ("photos", ("0.jpg", solid_image((10, 10, 10), fmt="JPEG"), "image/jpeg"))
    r = client.post("/api/v1/me/items", data={"id": "x1", "name": "Keys", "label": "keys"}, files=[photo], headers=h)
    assert r.json()["error"]["code"] == "unsupported_class"
    r = client.post("/api/v1/me/items", data={"id": "bad id!", "name": "P", "label": "cell phone"},
                    files=[photo], headers=h)
    assert r.status_code == 422
    r = client.post("/api/v1/me/items", data={"id": "x2", "name": "P", "label": "cell phone"},
                    files=[("photos", ("0.jpg", b"not an image", "image/jpeg"))], headers=h)
    assert r.json()["error"]["code"] == "invalid_image"
    r = client.post("/api/v1/me/items", data={"id": "x3", "name": "P", "label": "cell phone"}, files=[photo])
    assert r.status_code == 401
