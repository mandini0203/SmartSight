from datetime import date

import pytest

from app.services.accounts.nic import NicError, age_on, decode_nic

TODAY = date(2026, 10, 23)


@pytest.mark.parametrize("nic, birthday, gender, fmt", [
    ("199800100123", date(1998, 1, 1), "male", "new"),
    ("981234567V", date(1998, 5, 2), "male", "old"),  # day 123 with a 29-day February
    ("986234567v", date(1998, 5, 2), "female", "old"),  # 623 - 500
    ("200005901234", date(2000, 2, 28), "male", "new"),
    ("200006000000", date(2000, 2, 29), "male", "new"),  # day 60 exists in a leap year
    ("200206101234", date(2002, 3, 1), "male", "new"),  # day 61 is 1 March in every year
    ("19968660 1234", date(1996, 12, 31), "female", "new"),  # 866 - 500 = 366; spaces ignored
    ("853660000X", date(1985, 12, 31), "male", "old"),
])
def test_decodes_valid_numbers(nic, birthday, gender, fmt):
    info = decode_nic(nic, today=TODAY)
    assert (info.birthday, info.gender, info.format) == (birthday, gender, fmt)
    assert " " not in info.nic and info.nic == info.nic.upper()


@pytest.mark.parametrize("nic", [
    "", "12345", "98123456V7", "981234567A", "19981234567", "1998123456789",
    "980004567V",  # day 0
    "983674567V",  # day 367
    "985004567V",  # 500 -> day 0
    "200206001234",  # day 60 = 29 February 2002, which does not exist
    "300012301234",  # in the future
])
def test_rejects_invalid_numbers(nic):
    with pytest.raises(NicError):
        decode_nic(nic, today=TODAY)


def test_age():
    assert age_on(date(1998, 10, 23), TODAY) == 28
    assert age_on(date(1998, 10, 24), TODAY) == 27
