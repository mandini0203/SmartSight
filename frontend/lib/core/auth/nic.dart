/// Sri Lankan National Identity Card (NIC) number decoding. Mirrors the
/// backend's `app/services/accounts/nic.py`, which re-checks everything.
///
/// * old: `YYDDDSSSCV` — 9 digits and V or X, e.g. 981234567V (year 19YY)
/// * new: `YYYYDDDSSSSC` — 12 digits, e.g. 199812345678
///
/// `DDD` is the day of the birth year, plus 500 for women, counted as if
/// February always has 29 days: day 60 is 29 February and day 61 is 1 March.
library;

const _monthDays = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
final _old = RegExp(r'^\d{9}[VX]$');
final _new = RegExp(r'^\d{12}$');

enum NicGender { male, female }

class NicInfo {
  const NicInfo({required this.nic, required this.birthday, required this.gender, required this.isOldFormat});
  final String nic;
  final DateTime birthday;
  final NicGender gender;
  final bool isOldFormat;
}

class NicResult {
  const NicResult._(this.info, this.error);
  final NicInfo? info;

  /// Speakable reason the number is invalid; null when valid.
  final String? error;
  bool get isValid => info != null;
}

String normaliseNic(String raw) => raw.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();

NicResult decodeNic(String raw, {DateTime? today}) {
  final s = normaliseNic(raw);
  int year, days;
  final bool old;
  if (_old.hasMatch(s)) {
    year = 1900 + int.parse(s.substring(0, 2));
    days = int.parse(s.substring(2, 5));
    old = true;
  } else if (_new.hasMatch(s)) {
    year = int.parse(s.substring(0, 4));
    days = int.parse(s.substring(4, 7));
    old = false;
  } else {
    return const NicResult._(
        null, 'Enter a 12-digit NIC such as 199812345678, or an old NIC such as 981234567V.');
  }

  var gender = NicGender.male;
  if (days > 500) {
    days -= 500;
    gender = NicGender.female;
  }
  if (days < 1 || days > 366) {
    return const NicResult._(null, 'That NIC number is not valid: its birth-day digits are out of range.');
  }
  var month = 1;
  for (final length in _monthDays) {
    if (days <= length) break;
    days -= length;
    month++;
  }
  final birthday = DateTime(year, month, days);
  if (birthday.month != month) {
    // DateTime rolled 29 February over to 1 March: not a leap year.
    return const NicResult._(null, 'That NIC number is not valid: it gives a date that does not exist.');
  }
  final now = today ?? DateTime.now();
  if (year < 1900 || birthday.isAfter(DateTime(now.year, now.month, now.day))) {
    return const NicResult._(null, 'That NIC number is not valid: it gives a birth date in the future.');
  }
  return NicResult._(NicInfo(nic: s, birthday: birthday, gender: gender, isOldFormat: old), null);
}

int ageOn(DateTime birthday, {DateTime? today}) {
  final t = today ?? DateTime.now();
  var age = t.year - birthday.year;
  if (t.month < birthday.month || (t.month == birthday.month && t.day < birthday.day)) age--;
  return age;
}
