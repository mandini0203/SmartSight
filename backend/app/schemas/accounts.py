"""Request and response models for user accounts and profiles.

Validation messages are written to be read out to the user as they are.
"""

from __future__ import annotations

import re
from datetime import date, datetime
from enum import Enum

from pydantic import BaseModel, EmailStr, Field, field_validator, model_validator

from app.services.accounts.nic import NicError, age_on, decode_nic

_NAME = re.compile(r"[^\W\d_]+(?:[ '.\-][^\W\d_]+)*\.?")
_POSTAL = re.compile(r"\d{5}")
_PHONE = re.compile(r"\+\d{9,15}")


class Gender(str, Enum):
    MALE = "male"
    FEMALE = "female"
    OTHER = "other"
    PREFER_NOT_TO_SAY = "prefer_not_to_say"


class EyesightLevel(str, Enum):
    """Based on the WHO ICD-11 categories of distance vision impairment."""

    NONE = "none"  # better than 6/12
    MILD = "mild"  # worse than 6/12
    MODERATE = "moderate"  # worse than 6/18
    SEVERE = "severe"  # worse than 6/60
    BLIND = "blind"  # worse than 3/60
    LIGHT_PERCEPTION = "light_perception"  # light perception only
    TOTAL = "total"  # no light perception
    PREFER_NOT_TO_SAY = "prefer_not_to_say"


def normalise_phone(raw: str) -> str:
    """Sri Lankan local numbers (0771234567) become +94771234567."""
    s = re.sub(r"[\s\-()]", "", raw)
    if s.startswith("00"):
        s = "+" + s[2:]
    elif re.fullmatch(r"0\d{9}", s):
        s = "+94" + s[1:]
    elif re.fullmatch(r"94\d{9}", s):
        s = "+" + s
    if not _PHONE.fullmatch(s):
        raise ValueError("Enter a phone number such as 0771234567 or +94771234567.")
    return s


def _clean(value: str | None) -> str | None:
    if value is None:
        return None
    value = re.sub(r"\s+", " ", value).strip()
    return value or None


class ProfileFields(BaseModel):
    """Personal details. Birthday and gender are derived from the NIC when
    they are not given, and must agree with it when they are."""

    first_name: str = Field(..., max_length=60)
    last_name: str = Field(..., max_length=60)
    nic: str = Field(..., max_length=20, description="Sri Lankan NIC, old (981234567V) or new (199812345678).")
    birthday: date | None = Field(None, description="Filled from the NIC when omitted.")
    gender: Gender | None = Field(None, description="Filled from the NIC when omitted.")
    address_line1: str = Field(..., max_length=120, description="House number and street.")
    address_line2: str | None = Field(None, max_length=120, description="Area or village.")
    address_line3: str | None = Field(None, max_length=120, description="Town or city.")
    postal_code: str = Field(..., max_length=10)
    mobile: str = Field(..., max_length=24)
    whatsapp_same_as_mobile: bool = False
    whatsapp: str | None = Field(None, max_length=24)
    bmi: float | None = Field(None, description="Body mass index, optional.")
    eyesight: EyesightLevel | None = None

    @field_validator("first_name", "last_name")
    @classmethod
    def _name(cls, v: str, info) -> str:
        v = _clean(v) or ""
        label = info.field_name.replace("_", " ")
        if not v:
            raise ValueError(f"Enter your {label}.")
        if not _NAME.fullmatch(v):
            raise ValueError(f"Your {label} can only contain letters, spaces, hyphens and apostrophes.")
        return v

    @field_validator("address_line1")
    @classmethod
    def _address1(cls, v: str) -> str:
        v = _clean(v)
        if not v:
            raise ValueError("Enter the first line of your home address.")
        return v

    @field_validator("address_line2", "address_line3")
    @classmethod
    def _address_optional(cls, v: str | None) -> str | None:
        return _clean(v)

    @field_validator("postal_code")
    @classmethod
    def _postal(cls, v: str) -> str:
        v = re.sub(r"\s", "", v)
        if not _POSTAL.fullmatch(v):
            raise ValueError("Enter a 5-digit postal code, for example 10115.")
        return v

    @field_validator("mobile")
    @classmethod
    def _mobile(cls, v: str) -> str:
        return normalise_phone(v)

    @field_validator("whatsapp")
    @classmethod
    def _whatsapp(cls, v: str | None) -> str | None:
        v = _clean(v)
        return normalise_phone(v) if v else None

    @field_validator("bmi")
    @classmethod
    def _bmi(cls, v: float | None) -> float | None:
        if v is not None and not 10 <= v <= 80:
            raise ValueError("BMI must be between 10 and 80.")
        return round(v, 1) if v is not None else None

    @model_validator(mode="after")
    def _derive(self) -> "ProfileFields":
        try:
            info = decode_nic(self.nic)
        except NicError as exc:
            raise ValueError(str(exc)) from None
        self.nic = info.nic
        if self.birthday is None:
            self.birthday = info.birthday
        elif self.birthday != info.birthday:
            raise ValueError(f"The birthday does not match the NIC, which gives {info.birthday:%d %B %Y}.")
        if self.gender is None:
            self.gender = Gender(info.gender)
        elif self.gender in (Gender.MALE, Gender.FEMALE) and self.gender.value != info.gender:
            raise ValueError(f"The gender does not match the NIC, which is registered as {info.gender}.")
        if self.whatsapp_same_as_mobile:
            self.whatsapp = self.mobile
        return self


class RegisterRequest(ProfileFields):
    email: EmailStr
    password: str = Field(..., max_length=128)

    @field_validator("email")
    @classmethod
    def _email(cls, v: str) -> str:
        return v.lower()

    @field_validator("password")
    @classmethod
    def _password(cls, v: str) -> str:
        if len(v) < 8 or not (re.search(r"[A-Za-z]", v) and re.search(r"\d", v)):
            raise ValueError("Use a password with at least 8 characters, including a letter and a number.")
        return v


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=1, max_length=128)


class GoogleLoginRequest(BaseModel):
    id_token: str = Field(..., min_length=20, max_length=4096)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(..., min_length=20, max_length=200)


class UserProfile(BaseModel):
    id: str
    email: str
    first_name: str
    last_name: str
    nic: str | None
    birthday: date | None
    age: int | None
    gender: Gender | None
    address_line1: str | None
    address_line2: str | None
    address_line3: str | None
    postal_code: str | None
    mobile: str | None
    whatsapp: str | None
    whatsapp_same_as_mobile: bool
    bmi: float | None
    eyesight: EyesightLevel | None
    has_password: bool
    google_linked: bool
    profile_complete: bool = Field(..., description="False for new Google accounts until the profile is filled in.")
    created_at: datetime

    @classmethod
    def from_user(cls, u) -> "UserProfile":
        return cls(
            id=u.id, email=u.email, first_name=u.first_name, last_name=u.last_name, nic=u.nic,
            birthday=u.birthday, age=age_on(u.birthday) if u.birthday else None,
            gender=u.gender, address_line1=u.address_line1, address_line2=u.address_line2,
            address_line3=u.address_line3, postal_code=u.postal_code, mobile=u.mobile, whatsapp=u.whatsapp,
            whatsapp_same_as_mobile=u.whatsapp_same_as_mobile, bmi=u.bmi, eyesight=u.eyesight,
            has_password=u.password_hash is not None, google_linked=u.google_sub is not None,
            profile_complete=u.profile_complete, created_at=u.created_at,
        )


class AuthResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int = Field(..., description="Access-token lifetime in seconds.")
    user: UserProfile
    is_new_user: bool = False


class UserItem(BaseModel):
    id: str
    name: str
    label: str
    photo_count: int
    created_at: datetime
