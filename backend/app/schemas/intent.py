from __future__ import annotations

from enum import Enum

from pydantic import BaseModel, Field, field_validator

from app.schemas.common import ComponentInfo


class Intent(str, Enum):
    FIND_OBJECT = "find_object"
    FIND_EXIT = "find_exit"
    FIND_SEAT = "find_seat"
    IDENTIFY_COLOUR = "identify_colour"
    DESCRIBE_SURROUNDINGS = "describe_surroundings"
    READ_SIGNS = "read_signs"


class ResolutionStatus(str, Enum):
    RESOLVED = "RESOLVED"
    NEEDS_CLARIFICATION = "NEEDS_CLARIFICATION"
    UNSUPPORTED = "UNSUPPORTED"


class IntentRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=500, description="Recognised speech or typed text.")
    locale: str = Field("en", max_length=16)

    @field_validator("text")
    @classmethod
    def _not_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("text must not be blank")
        return v


class IntentSlots(BaseModel):
    target_object: str | None = Field(None, description="Object phrase as spoken, e.g. 'phone'.")
    target_label: str | None = Field(None, description="Matching detector (COCO) label, e.g. 'cell phone'.")
    target_supported_by_detector: bool | None = None
    personal: bool = Field(False, description="True when the user referred to their own item ('my phone').")


class IntentAlternative(BaseModel):
    intent: Intent
    score: float


class IntentResponse(BaseModel):
    status: ResolutionStatus
    intent: Intent | None
    slots: IntentSlots
    confidence: float = Field(..., ge=0, le=1)
    matched_rules: list[str]
    alternatives: list[IntentAlternative]
    clarification_question: str | None = None
    message: str
    normalised_text: str
    resolver: ComponentInfo
