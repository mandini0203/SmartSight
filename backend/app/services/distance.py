"""Absolute distance estimation — a separate, replaceable component.

Method: calibrated monocular estimation with a pinhole camera model and
typical real-world object sizes ("known-size" ranging)::

    distance = real_size_m * focal_length_px / size_px
    focal_length_px = (long_image_side_px / 2) / tan(long_side_fov / 2)

Why this method for the first version (see docs/DISTANCE_ESTIMATION.md):
  * it needs no extra model, sensor or training data;
  * it works on any phone once the camera field of view is calibrated;
  * its uncertainty can be stated explicitly from the spread of object sizes.

Learned monocular depth (e.g. MiDaS / Depth Anything) mostly yields *relative*
depth, needs metric fine-tuning to give metres, and costs far more compute.
ARCore Depth / ToF sensing is accurate but only on supported devices and has to
run on the phone. Both can later be added behind ``DistanceEstimator``.

Limitations: the estimate is only as good as the size prior. Objects cut off by
the frame edge, viewed at a steep angle, or atypically sized are wrong; such
cases are skipped or given low confidence.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from app.schemas.common import BoundingBox, ComponentInfo, DistanceEstimate, FrameInfo
from app.services.interfaces import DistanceEstimator


@dataclass(frozen=True)
class SizePrior:
    metres: float       # typical size
    low: float          # plausible smaller size
    high: float         # plausible larger size
    axis: str           # "height" or "width" of the box to use
    reliability: float  # 0..1 prior trust in this class's size


# Typical sizes of upright objects. Sources: common furniture / anthropometric
# dimensions; deliberately wide ranges.
SIZE_PRIORS: dict[str, SizePrior] = {
    "person": SizePrior(1.70, 1.50, 1.90, "height", 0.7),
    "chair": SizePrior(0.90, 0.75, 1.10, "height", 0.55),
    "couch": SizePrior(0.85, 0.70, 1.00, "height", 0.45),
    "bench": SizePrior(0.85, 0.40, 1.00, "height", 0.35),
    "dining table": SizePrior(0.75, 0.65, 0.80, "height", 0.4),
    "bed": SizePrior(0.60, 0.40, 1.20, "height", 0.3),
    "toilet": SizePrior(0.75, 0.65, 0.85, "height", 0.5),
    "refrigerator": SizePrior(1.75, 1.40, 2.00, "height", 0.5),
    "tv": SizePrior(0.65, 0.35, 1.00, "height", 0.3),
    "bottle": SizePrior(0.25, 0.15, 0.33, "height", 0.4),
    "cup": SizePrior(0.10, 0.07, 0.14, "height", 0.35),
    "laptop": SizePrior(0.33, 0.28, 0.40, "width", 0.35),
    "backpack": SizePrior(0.45, 0.35, 0.55, "height", 0.35),
    "suitcase": SizePrior(0.65, 0.45, 0.80, "height", 0.35),
    "potted plant": SizePrior(0.50, 0.20, 1.20, "height", 0.2),
    "door": SizePrior(2.03, 1.95, 2.40, "height", 0.6),
    "exit sign": SizePrior(0.20, 0.15, 0.30, "height", 0.4),
    "stop sign": SizePrior(0.75, 0.60, 0.90, "width", 0.5),
    "car": SizePrior(1.50, 1.40, 1.90, "height", 0.45),
    "bus": SizePrior(3.00, 2.80, 3.60, "height", 0.45),
    "bicycle": SizePrior(1.00, 0.90, 1.15, "height", 0.4),
    "dog": SizePrior(0.55, 0.25, 0.80, "height", 0.2),
}

EDGE_MARGIN_PX = 3.0
FOV_UNCERTAINTY = 0.08  # +/-8 % focal-length uncertainty after calibration


class KnownSizeDistanceEstimator(DistanceEstimator):
    def __init__(self, default_fov_degrees: float) -> None:
        self.default_fov = default_fov_degrees

    @property
    def info(self) -> ComponentInfo:
        return ComponentInfo(
            name="known_size_pinhole",
            version="1.0",
            is_trained_model=False,
            description="Calibrated monocular distance from typical object sizes and camera field of view.",
        )

    def estimate(
        self, label: str, bbox: BoundingBox, frame: FrameInfo, fov_degrees: float | None = None
    ) -> DistanceEstimate | None:
        prior = SIZE_PRIORS.get(label)
        if prior is None:
            return None
        truncated_v = bbox.y1 <= EDGE_MARGIN_PX or bbox.y2 >= frame.height - EDGE_MARGIN_PX
        truncated_h = bbox.x1 <= EDGE_MARGIN_PX or bbox.x2 >= frame.width - EDGE_MARGIN_PX
        if (prior.axis == "height" and truncated_v) or (prior.axis == "width" and truncated_h):
            # The visible size is smaller than the real object, so the estimate would be too far.
            return None
        size_px = bbox.height if prior.axis == "height" else bbox.width
        if size_px < 8:
            return None

        fov = fov_degrees or self.default_fov
        focal_px = (max(frame.width, frame.height) / 2) / math.tan(math.radians(fov) / 2)
        d = prior.metres * focal_px / size_px
        low = prior.low * focal_px / size_px * (1 - FOV_UNCERTAINTY)
        high = prior.high * focal_px / size_px * (1 + FOV_UNCERTAINTY)

        confidence = prior.reliability
        if truncated_h or truncated_v:
            confidence *= 0.7
        if d > 10:
            confidence *= 0.6  # small boxes: pixel errors dominate
        assumptions = [
            f"Assumes a typical {label} {prior.axis} of {prior.metres:.2f} m "
            f"(range {prior.low:.2f}-{prior.high:.2f} m).",
            f"Assumes a camera field of view of {fov:.0f} degrees on the long image side.",
            "Assumes the object is upright and roughly facing the camera.",
        ]
        return DistanceEstimate(
            metres=round(d, 2),
            low_metres=round(low, 2),
            high_metres=round(high, 2),
            confidence=round(min(max(confidence, 0.0), 1.0), 2),
            method="known_size_pinhole",
            assumptions=assumptions,
        )


def spoken_distance(est: DistanceEstimate) -> str:
    """Round to a speakable value; never more precise than the estimate supports."""
    m = est.metres
    if m < 1:
        return "less than a metre away"
    if m < 3:
        value = round(m * 2) / 2
        return "about 1 metre away" if value == 1 else f"about {value:g} metres away"
    if m < 10:
        return f"about {round(m):d} metres away"
    return "more than 10 metres away"
