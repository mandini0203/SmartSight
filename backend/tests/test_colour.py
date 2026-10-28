import io

import pytest
from PIL import Image, ImageDraw


def post(client, data, **form):
    return client.post("/api/v1/colour/identify", files={"image": ("c.png", data, "image/png")}, data=form)


@pytest.mark.parametrize(
    "rgb,family",
    [((210, 25, 25), "red"), ((30, 60, 200), "blue"), ((30, 150, 60), "green"), ((250, 220, 40), "yellow"),
     ((15, 15, 15), "black"), ((245, 245, 245), "white"), ((128, 128, 128), "grey"), ((240, 130, 30), "orange")],
)
def test_solid_colours(client, solid_image, rgb, family):
    r = post(client, solid_image(rgb))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["primary"]["family"] == family, body["primary"]
    assert body["region_source"] == "centre"
    assert body["identifier"]["is_trained_model"] is False


def test_bbox_region_selects_object(client):
    img = Image.new("RGB", (400, 300), (245, 245, 245))
    ImageDraw.Draw(img).rectangle([250, 100, 350, 200], fill=(200, 20, 20))
    buf = io.BytesIO()
    img.save(buf, "PNG")
    body = post(client, buf.getvalue(), x1="250", y1="100", x2="350", y2="200").json()
    assert body["primary"]["family"] == "red"
    assert body["region_source"] == "bbox"
    # Centre of the same image is white.
    assert post(client, buf.getvalue()).json()["primary"]["family"] == "white"


def test_normalised_point(client):
    img = Image.new("RGB", (400, 300), (245, 245, 245))
    ImageDraw.Draw(img).rectangle([0, 0, 120, 100], fill=(30, 60, 200))
    buf = io.BytesIO()
    img.save(buf, "PNG")
    body = post(client, buf.getvalue(), point_x="0.1", point_y="0.15", normalised="true").json()
    assert body["primary"]["family"] == "blue"


def test_partial_box_rejected(client, solid_image):
    r = post(client, solid_image((1, 2, 3)), x1="1", y1="2")
    assert r.status_code == 422


def test_inverted_box_rejected(client, solid_image):
    r = post(client, solid_image((1, 2, 3)), x1="100", y1="10", x2="50", y2="60")
    assert r.status_code == 422


def test_dark_image_lowers_confidence(client, solid_image):
    body = post(client, solid_image((5, 5, 8))).json()
    assert any("dark" in c for c in body["caveats"])


def test_deterministic(client, bus_jpg):
    a = client.post("/api/v1/colour/identify", files={"image": ("b.jpg", bus_jpg, "image/jpeg")}).json()
    b = client.post("/api/v1/colour/identify", files={"image": ("b.jpg", bus_jpg, "image/jpeg")}).json()
    assert a["colours"] == b["colours"]
