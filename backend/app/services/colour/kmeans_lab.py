"""Dominant-colour identification with k-means in CIELAB space.

Deterministic classical image processing (no trained model):
  1. Crop the region; keep an inner ellipse to reduce background pixels at the
     corners of a bounding box.
  2. Downsample, convert sRGB -> CIELAB (D65).
  3. k-means (k = 4, fixed seed, k-means++ init) on Lab pixels.
  4. Name each cluster centre by the nearest colour in a fixed palette using
     CIEDE2000.
"""

from __future__ import annotations

import cv2
import numpy as np

from app.schemas.colour import ColourResponse, ColourSwatch
from app.schemas.common import BoundingBox, ComponentInfo, FrameInfo
from app.services.interfaces import ColourIdentifier

# (name, family, sRGB)
PALETTE: list[tuple[str, str, tuple[int, int, int]]] = [
    ("black", "black", (20, 20, 20)),
    ("charcoal grey", "grey", (64, 64, 64)),
    ("grey", "grey", (128, 128, 128)),
    ("light grey", "grey", (192, 192, 192)),
    ("white", "white", (245, 245, 245)),
    ("cream", "white", (245, 235, 205)),
    ("red", "red", (200, 30, 30)),
    ("dark red", "red", (120, 15, 20)),
    ("pink", "pink", (240, 150, 180)),
    ("hot pink", "pink", (230, 60, 140)),
    ("orange", "orange", (240, 130, 30)),
    ("brown", "brown", (120, 70, 35)),
    ("dark brown", "brown", (70, 40, 20)),
    ("beige", "brown", (215, 195, 160)),
    ("tan", "brown", (190, 150, 100)),
    ("yellow", "yellow", (245, 215, 40)),
    ("gold", "yellow", (200, 160, 50)),
    ("olive green", "green", (110, 115, 40)),
    ("light green", "green", (140, 210, 120)),
    ("green", "green", (40, 150, 60)),
    ("dark green", "green", (20, 80, 35)),
    ("teal", "blue", (20, 130, 130)),
    ("turquoise", "blue", (60, 200, 200)),
    ("light blue", "blue", (150, 195, 235)),
    ("blue", "blue", (40, 90, 200)),
    ("navy blue", "blue", (25, 35, 90)),
    ("purple", "purple", (110, 50, 150)),
    ("lavender", "purple", (185, 160, 220)),
    ("maroon", "red", (110, 30, 50)),
    ("silver", "grey", (170, 175, 180)),
]

K = 4
MAX_PIXELS_SIDE = 96


def srgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    """uint8 RGB array (..., 3) -> float Lab (L in 0..100)."""
    arr = rgb.reshape(-1, 1, 3).astype(np.float32) / 255.0
    lab = cv2.cvtColor(arr, cv2.COLOR_RGB2Lab)  # float input -> L 0..100, a/b ~ -127..127
    return lab.reshape(rgb.shape[:-1] + (3,))


def delta_e_2000(lab1: np.ndarray, lab2: np.ndarray) -> np.ndarray:
    """CIEDE2000 between broadcastable Lab arrays (..., 3)."""
    L1, a1, b1 = np.moveaxis(lab1, -1, 0)
    L2, a2, b2 = np.moveaxis(lab2, -1, 0)
    C1 = np.hypot(a1, b1)
    C2 = np.hypot(a2, b2)
    Cm = (C1 + C2) / 2
    G = 0.5 * (1 - np.sqrt(Cm**7 / (Cm**7 + 25**7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = np.hypot(a1p, b1), np.hypot(a2p, b2)
    h1p = np.degrees(np.arctan2(b1, a1p)) % 360
    h2p = np.degrees(np.arctan2(b2, a2p)) % 360
    dLp = L2 - L1
    dCp = C2p - C1p
    dh = h2p - h1p
    dh = np.where(C1p * C2p == 0, 0, np.where(dh > 180, dh - 360, np.where(dh < -180, dh + 360, dh)))
    dHp = 2 * np.sqrt(C1p * C2p) * np.sin(np.radians(dh) / 2)
    Lpm = (L1 + L2) / 2
    Cpm = (C1p + C2p) / 2
    hsum = h1p + h2p
    hpm = np.where(
        C1p * C2p == 0, hsum,
        np.where(np.abs(h1p - h2p) <= 180, hsum / 2, np.where(hsum < 360, (hsum + 360) / 2, (hsum - 360) / 2)),
    )
    T = (1 - 0.17 * np.cos(np.radians(hpm - 30)) + 0.24 * np.cos(np.radians(2 * hpm))
         + 0.32 * np.cos(np.radians(3 * hpm + 6)) - 0.20 * np.cos(np.radians(4 * hpm - 63)))
    d_theta = 30 * np.exp(-(((hpm - 275) / 25) ** 2))
    Rc = 2 * np.sqrt(Cpm**7 / (Cpm**7 + 25**7))
    Sl = 1 + (0.015 * (Lpm - 50) ** 2) / np.sqrt(20 + (Lpm - 50) ** 2)
    Sc = 1 + 0.045 * Cpm
    Sh = 1 + 0.015 * Cpm * T
    Rt = -np.sin(np.radians(2 * d_theta)) * Rc
    return np.sqrt((dLp / Sl) ** 2 + (dCp / Sc) ** 2 + (dHp / Sh) ** 2 + Rt * (dCp / Sc) * (dHp / Sh))


_PALETTE_RGB = np.array([p[2] for p in PALETTE], dtype=np.uint8)
_PALETTE_LAB = srgb_to_lab(_PALETTE_RGB)


def name_colour(lab: np.ndarray) -> tuple[int, float]:
    d = delta_e_2000(lab[None, :], _PALETTE_LAB)
    i = int(np.argmin(d))
    return i, float(d[i])


def lab_to_rgb(lab: np.ndarray) -> tuple[int, int, int]:
    rgb = cv2.cvtColor(lab.reshape(1, 1, 3).astype(np.float32), cv2.COLOR_Lab2RGB).reshape(3)
    r, g, b = (np.clip(rgb, 0, 1) * 255).round().astype(int)
    return int(r), int(g), int(b)


class KMeansLabColourIdentifier(ColourIdentifier):
    @property
    def info(self) -> ComponentInfo:
        return ComponentInfo(
            name="kmeans_lab",
            version="1.0",
            is_trained_model=False,
            description="k-means clustering in CIELAB with CIEDE2000 nearest named colour.",
        )

    def identify(self, image: np.ndarray, region: BoundingBox, region_source: str, frame: FrameInfo) -> ColourResponse:
        x1, y1 = int(region.x1), int(region.y1)
        x2, y2 = int(np.ceil(region.x2)), int(np.ceil(region.y2))
        patch = image[y1:y2, x1:x2]
        h, w = patch.shape[:2]
        scale = min(1.0, MAX_PIXELS_SIDE / max(h, w))
        if scale < 1.0:
            patch = cv2.resize(patch, (max(1, int(w * scale)), max(1, int(h * scale))), interpolation=cv2.INTER_AREA)
        h, w = patch.shape[:2]
        yy, xx = np.mgrid[0:h, 0:w]
        # Inner ellipse covering ~60 % of the box keeps the object and drops corner background.
        mask = ((xx - (w - 1) / 2) / (0.5 * w * 0.85)) ** 2 + ((yy - (h - 1) / 2) / (0.5 * h * 0.85)) ** 2 <= 1
        pixels = patch[mask] if mask.sum() >= 16 else patch.reshape(-1, 3)
        lab = srgb_to_lab(pixels.reshape(-1, 1, 3)).reshape(-1, 3).astype(np.float32)

        k = int(min(K, max(1, len(lab) // 8)))
        cv2.setRNGSeed(12345)
        criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.5)
        _, labels, centres = cv2.kmeans(lab, k, None, criteria, 3, cv2.KMEANS_PP_CENTERS)
        counts = np.bincount(labels.ravel(), minlength=k).astype(float)
        fractions = counts / counts.sum()

        swatches: list[ColourSwatch] = []
        for idx in np.argsort(-fractions):
            if fractions[idx] < 0.05:
                continue
            pi, de = name_colour(centres[idx])
            rgb = lab_to_rgb(centres[idx])
            name, family, _ = PALETTE[pi]
            # Merge clusters that map to the same name.
            existing = next((s for s in swatches if s.name == name), None)
            if existing:
                existing.fraction = round(existing.fraction + float(fractions[idx]), 3)
                continue
            swatches.append(ColourSwatch(
                name=name, family=family, hex="#%02x%02x%02x" % rgb, rgb=rgb,
                fraction=round(float(fractions[idx]), 3), delta_e=round(de, 1),
            ))
        swatches.sort(key=lambda s: s.fraction, reverse=True)
        primary = swatches[0]

        mean_l = float(lab[:, 0].mean())
        caveats = [
            "Colour depends on lighting and the camera's white balance.",
            "The region may include background or shadows.",
        ]
        confidence = primary.fraction * max(0.2, 1 - primary.delta_e / 30)
        if mean_l < 20:
            caveats.insert(0, "The region is very dark; the colour may be unreliable.")
            confidence *= 0.5
        elif mean_l > 92:
            caveats.insert(0, "The region is very bright or over-exposed; the colour may be unreliable.")
            confidence *= 0.6
        confidence = round(min(max(confidence, 0.0), 1.0), 2)

        if len(swatches) > 1 and swatches[1].fraction >= 0.25:
            message = f"Mostly {primary.name}, with some {swatches[1].name}."
        else:
            message = f"It looks {primary.name}."
        if confidence < 0.35:
            message += " I'm not confident about this."

        return ColourResponse(
            frame=frame, region=region, region_source=region_source, primary=primary,
            colours=swatches, confidence=confidence, message=message,
            identifier=self.info, caveats=caveats,
        )
