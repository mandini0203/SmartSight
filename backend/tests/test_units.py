"""Unit tests for pure components (no HTTP)."""

import math

import numpy as np
import pytest

from app.schemas.common import BoundingBox, FrameInfo
from app.services.colour.kmeans_lab import delta_e_2000
from app.services.distance import KnownSizeDistanceEstimator, spoken_distance
from app.services.intent.rule_based import normalise
from app.services.spatial import relative_position

FRAME = FrameInfo(width=1000, height=750)


@pytest.mark.parametrize("cx,expected", [(50, "left"), (300, "slightly_left"), (500, "centre"),
                                         (700, "slightly_right"), (950, "right")])
def test_horizontal_bands(cx, expected):
    pos = relative_position(BoundingBox(x1=cx - 10, y1=300, x2=cx + 10, y2=400), FRAME)
    assert pos.horizontal.value == expected


def test_clock_direction():
    centre = relative_position(BoundingBox(x1=490, y1=300, x2=510, y2=400), FRAME)
    assert centre.clock_direction == 12 and centre.clock_label == "12 o'clock"
    right = relative_position(BoundingBox(x1=960, y1=300, x2=1000, y2=400), FRAME)
    assert right.clock_direction == 13 and right.clock_label == "1 o'clock"
    left = relative_position(BoundingBox(x1=0, y1=300, x2=40, y2=400), FRAME)
    assert left.clock_direction == 11


def test_known_size_distance_matches_pinhole_geometry():
    est = KnownSizeDistanceEstimator(66.0)
    # A 1.70 m person, 3 m away: size_px = 1.7 * f / 3
    f = 500 / math.tan(math.radians(33))
    h = 1.7 * f / 3.0
    box = BoundingBox(x1=450, y1=100, x2=550, y2=100 + h)
    d = est.estimate("person", box, FRAME)
    assert d is not None
    assert d.metres == pytest.approx(3.0, abs=0.01)
    assert d.low_metres < 3.0 < d.high_metres


def test_distance_unknown_class():
    assert KnownSizeDistanceEstimator(66).estimate("frisbee", BoundingBox(x1=1, y1=10, x2=50, y2=60), FRAME) is None


@pytest.mark.parametrize("m,text", [(0.6, "less than a metre away"), (1.1, "about 1 metre away"),
                                    (2.2, "about 2 metres away"), (2.3, "about 2.5 metres away"),
                                    (6.4, "about 6 metres away"), (14, "more than 10 metres away")])
def test_spoken_distance(m, text):
    from app.schemas.common import DistanceEstimate

    est = DistanceEstimate(metres=m, low_metres=m * 0.8, high_metres=m * 1.2, confidence=0.5, method="t", assumptions=[])
    assert spoken_distance(est) == text


def test_ciede2000_reference_pair():
    # Sharma et al. (2005) test data, pair 1: expected dE00 = 2.0425
    lab1 = np.array([50.0, 2.6772, -79.7751])
    lab2 = np.array([50.0, 0.0, -82.7485])
    assert float(delta_e_2000(lab1, lab2)) == pytest.approx(2.0425, abs=1e-3)


@pytest.mark.parametrize("raw,norm", [
    ("  Hey SmartSight, where's my PHONE?? ", "where is my phone"),
    ("Could you please find the exit", "find the exit"),
    ("What’s in front of me", "what is in front of me"),
])
def test_normalise(raw, norm):
    assert normalise(raw) == norm
