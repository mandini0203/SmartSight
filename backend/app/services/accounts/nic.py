"""Sri Lankan National Identity Card (NIC) number decoding.

Two formats are in use:

* old: ``YYDDDSSSCV`` -- 9 digits and a letter V or X, e.g. ``981234567V``.
  The birth year is 19YY.
* new: ``YYYYDDDSSSSC`` -- 12 digits, e.g. ``199812345678``.

``DDD`` is the day of the birth year, plus 500 for women. Days are counted
as if February always has 29 days, so a day number maps to the same calendar
date in every year: day 60 is 29 February (impossible in a non-leap year)
and day 61 is 1 March.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date

_MONTH_DAYS = (31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
_OLD = re.compile(r"\d{9}[VX]")
_NEW = re.compile(r"\d{12}")

FORMAT_HINT = "Enter a 12-digit NIC such as 199812345678, or an old NIC such as 981234567V."


class NicError(ValueError):
    pass


@dataclass(frozen=True)
class NicInfo:
    nic: str  # normalised: no spaces, upper-case letter
    birthday: date
    gender: str  # "male" | "female"
    format: str  # "old" | "new"


def normalise_nic(raw: str) -> str:
    return re.sub(r"[\s\-]", "", raw).upper()


def decode_nic(raw: str, today: date | None = None) -> NicInfo:
    s = normalise_nic(raw)
    if _OLD.fullmatch(s):
        year, days, fmt = 1900 + int(s[:2]), int(s[2:5]), "old"
    elif _NEW.fullmatch(s):
        year, days, fmt = int(s[:4]), int(s[4:7]), "new"
    else:
        raise NicError(f"That NIC number is not in a valid format. {FORMAT_HINT}")

    gender = "male"
    if days > 500:
        days -= 500
        gender = "female"
    if not 1 <= days <= 366:
        raise NicError("That NIC number is not valid: its birth-day digits are out of range.")

    month = 1
    for length in _MONTH_DAYS:
        if days <= length:
            break
        days -= length
        month += 1
    try:
        birthday = date(year, month, days)
    except ValueError:  # 29 February in a non-leap year
        raise NicError("That NIC number is not valid: it gives a date that does not exist.") from None

    today = today or date.today()
    if year < 1900 or birthday > today:
        raise NicError("That NIC number is not valid: it gives a birth date in the future.")
    return NicInfo(nic=s, birthday=birthday, gender=gender, format=fmt)


def age_on(birthday: date, today: date | None = None) -> int:
    today = today or date.today()
    return today.year - birthday.year - ((today.month, today.day) < (birthday.month, birthday.day))
