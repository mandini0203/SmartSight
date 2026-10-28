from __future__ import annotations

from pydantic import BaseModel, Field

from app.schemas.common import BoundingBox, ComponentInfo, FrameInfo


class ColourSwatch(BaseModel):
    name: str = Field(..., description="Nearest named colour, e.g. 'navy blue'.")
    family: str = Field(..., description="Basic colour family, e.g. 'blue'.")
    hex: str
    rgb: tuple[int, int, int]
    fraction: float = Field(..., ge=0, le=1, description="Share of analysed pixels in this cluster.")
    delta_e: float = Field(..., ge=0, description="CIEDE2000 distance to the named colour.")


class ColourResponse(BaseModel):
    frame: FrameInfo
    region: BoundingBox
    region_source: str = Field(..., description="'bbox' (supplied), 'centre' (default) or 'detection'.")
    primary: ColourSwatch
    colours: list[ColourSwatch]
    confidence: float = Field(..., ge=0, le=1)
    message: str
    identifier: ComponentInfo
    caveats: list[str]
