"""Rule-based relative position from a bounding box.

All thresholds are fixed and documented here so that results are reproducible.
Positions are relative to the camera view, not to the user's body: the user
is assumed to hold the phone pointing forward.
"""

from __future__ import annotations

import math

from app.schemas.common import (
    ApparentSize,
    BoundingBox,
    FrameInfo,
    Horizontal,
    RelativePosition,
    Vertical,
)

# Horizontal bands on the normalised box centre (0 = left edge, 1 = right edge).
_H_BANDS = [
    (0.20, Horizontal.LEFT),
    (0.40, Horizontal.SLIGHTLY_LEFT),
    (0.60, Horizontal.CENTRE),
    (0.80, Horizontal.SLIGHTLY_RIGHT),
    (1.01, Horizontal.RIGHT),
]
_V_BANDS = [(1 / 3, Vertical.UPPER), (2 / 3, Vertical.MIDDLE), (1.01, Vertical.LOWER)]
LARGE_AREA = 0.25
MEDIUM_AREA = 0.04

_H_TEXT = {
    Horizontal.LEFT: "on your left",
    Horizontal.SLIGHTLY_LEFT: "slightly to your left",
    Horizontal.CENTRE: "straight ahead",
    Horizontal.SLIGHTLY_RIGHT: "slightly to your right",
    Horizontal.RIGHT: "on your right",
}
_V_TEXT = {
    Vertical.UPPER: "high in view",
    Vertical.MIDDLE: "at middle height",
    Vertical.LOWER: "low in view",
}


def horizontal_angle_degrees(cx_norm: float, frame: FrameInfo, long_side_fov: float) -> float:
    """Angle of the box centre from the optical axis using a pinhole model."""
    focal_px = (max(frame.width, frame.height) / 2) / math.tan(math.radians(long_side_fov) / 2)
    dx_px = (cx_norm - 0.5) * frame.width
    return math.degrees(math.atan2(dx_px, focal_px))


def clock_label(hour: int) -> str:
    h = hour if hour <= 12 else hour - 12
    return f"{h} o'clock"


def relative_position(bbox: BoundingBox, frame: FrameInfo, long_side_fov: float = 66.0) -> RelativePosition:
    cx, cy = bbox.centre
    cxn = min(max(cx / frame.width, 0.0), 1.0)
    cyn = min(max(cy / frame.height, 0.0), 1.0)
    horizontal = next(h for limit, h in _H_BANDS if cxn < limit)
    vertical = next(v for limit, v in _V_BANDS if cyn < limit)
    area_ratio = min(bbox.area / float(frame.width * frame.height), 1.0)
    size = (
        ApparentSize.LARGE
        if area_ratio >= LARGE_AREA
        else ApparentSize.MEDIUM
        if area_ratio >= MEDIUM_AREA
        else ApparentSize.SMALL
    )
    angle = horizontal_angle_degrees(cxn, frame, long_side_fov)
    hour = 12 + int(round(angle / 30.0))
    hour = min(max(hour, 9), 15)
    label = clock_label(hour)
    return RelativePosition(
        horizontal=horizontal,
        vertical=vertical,
        clock_direction=hour,
        clock_label=label,
        apparent_size=size,
        area_ratio=round(area_ratio, 4),
        description=f"{_H_TEXT[horizontal]}, {_V_TEXT[vertical]}, at {label}",
    )


def iou(a: BoundingBox, b: BoundingBox) -> float:
    inter = intersection_area(a, b)
    union = a.area + b.area - inter
    return inter / union if union > 0 else 0.0


def intersection_area(a: BoundingBox, b: BoundingBox) -> float:
    w = min(a.x2, b.x2) - max(a.x1, b.x1)
    h = min(a.y2, b.y2) - max(a.y1, b.y1)
    return max(w, 0.0) * max(h, 0.0)


def horizontal_overlap(a: BoundingBox, b: BoundingBox) -> float:
    """Overlap of the x-ranges as a fraction of the narrower box."""
    w = min(a.x2, b.x2) - max(a.x1, b.x1)
    return max(w, 0.0) / max(min(a.width, b.width), 1e-6)
