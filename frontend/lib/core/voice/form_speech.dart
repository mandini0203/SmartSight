/// Turns recognised speech into form values: "john dot perera at gmail dot
/// com" into an email address, "double seven one two..." into digits,
/// "twelfth of March nineteen ninety eight" into a date, and so on.
///
/// Every function is pure and deterministic, so it can be unit-tested.
library;

import '../auth/profile.dart';

const _digitWords = {
  'zero': '0', 'oh': '0', 'o': '0', 'nought': '0', 'one': '1', 'won': '1', 'two': '2', 'to': '2', 'too': '2',
  'three': '3', 'tree': '3', 'four': '4', 'for': '4', 'five': '5', 'six': '6', 'seven': '7', 'eight': '8',
  'ate': '8', 'nine': '9',
};

const _units = {
  'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
  'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
  'seventeen': 17, 'eighteen': 18, 'nineteen': 19,
};
const _tens = {
  'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
};
const _ordinals = {
  'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5, 'sixth': 6, 'seventh': 7, 'eighth': 8, 'ninth': 9,
  'tenth': 10, 'eleventh': 11, 'twelfth': 12, 'thirteenth': 13, 'fourteenth': 14, 'fifteenth': 15,
  'sixteenth': 16, 'seventeenth': 17, 'eighteenth': 18, 'nineteenth': 19, 'twentieth': 20, 'thirtieth': 30,
};
const _months = {
  'january': 1, 'jan': 1, 'february': 2, 'feb': 2, 'march': 3, 'mar': 3, 'april': 4, 'apr': 4, 'may': 5,
  'june': 6, 'jun': 6, 'july': 7, 'jul': 7, 'august': 8, 'aug': 8, 'september': 9, 'sept': 9, 'sep': 9,
  'october': 10, 'oct': 10, 'november': 11, 'nov': 11, 'december': 12, 'dec': 12,
};

List<String> _words(String s) =>
    s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9@.+\-_' ]"), ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// Digits from speech such as "double seven one, two three". Other words are dropped.
String spokenToDigits(String spoken) {
  final out = StringBuffer();
  var repeat = 1;
  for (final w in _words(spoken)) {
    if (w == 'double') {
      repeat = 2;
      continue;
    }
    if (w == 'triple') {
      repeat = 3;
      continue;
    }
    final digits = _digitWords[w] ?? w.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) continue;
    // "double 7" repeats only the first digit of the following token.
    out.write(digits[0] * repeat + digits.substring(1));
    repeat = 1;
  }
  return out.toString();
}

/// Phone number; "plus nine four seven seven..." keeps the leading +.
String spokenToPhone(String spoken) {
  final s = spoken.trim().toLowerCase();
  final plus = s.startsWith('+') || s.startsWith('plus');
  return '${plus ? '+' : ''}${spokenToDigits(s.replaceFirst(RegExp(r'^(\+|plus)'), ''))}';
}

/// NIC: digits, plus a final V or X for the old format.
String spokenToNic(String spoken) {
  final words = _words(spoken);
  var letter = '';
  if (words.isNotEmpty) {
    final last = words.last;
    if (const {'v', 'vee', 'we', 'wee', 'b'}.contains(last) || RegExp(r'^\d+v$').hasMatch(last)) letter = 'V';
    if (const {'x', 'ex', 'eggs', 'axe'}.contains(last) || RegExp(r'^\d+x$').hasMatch(last)) letter = 'X';
    if (letter.isNotEmpty && !RegExp(r'^\d+[vx]$').hasMatch(last)) words.removeLast();
  }
  return spokenToDigits(words.join(' ')) + letter;
}

/// Five-digit postal code.
String spokenToPostalCode(String spoken) => spokenToDigits(spoken);

/// "john dot perera at gmail dot com" -> john.perera@gmail.com
String spokenToEmail(String spoken) {
  var s = ' ${spoken.toLowerCase().trim()} ';
  const replacements = {
    ' at the rate of ': '@', ' at the rate ': '@', ' at sign ': '@', ' at ': '@',
    ' dot ': '.', ' full stop ': '.', ' period ': '.', ' point ': '.',
    ' underscore ': '_', ' under score ': '_', ' dash ': '-', ' hyphen ': '-', ' minus ': '-',
  };
  for (final e in replacements.entries) {
    while (s.contains(e.key)) {
      s = s.replaceAll(e.key, e.value);
    }
  }
  return s.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'[^a-z0-9@._+\-]'), '');
}

/// Capitalised name, letters, spaces, hyphens and apostrophes only.
String spokenToName(String spoken) {
  final cleaned = spoken.replaceAll(RegExp(r"[^\p{L} '\-]", unicode: true), ' ').trim();
  return cleaned
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

/// Free text such as an address line: tidied spacing, first letter capitalised.
String spokenToText(String spoken) {
  final s = spoken.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Speech recognisers insert spaces; passwords are taken without them.
String spokenToPassword(String spoken) => spoken.replaceAll(RegExp(r'\s+'), '');

int? _numberWords(List<String> words) {
  if (words.isEmpty) return null;
  var total = 0, current = 0;
  for (final w in words) {
    if (w == 'and') continue;
    final n = int.tryParse(w) ?? _units[w] ?? _tens[w];
    if (n != null) {
      current += n;
    } else if (w == 'hundred') {
      current = (current == 0 ? 1 : current) * 100;
    } else if (w == 'thousand') {
      total += (current == 0 ? 1 : current) * 1000;
      current = 0;
    } else {
      return null;
    }
  }
  return total + current;
}

/// "twenty two point five" or "22.5" -> 22.5
double? spokenToNumber(String spoken) {
  final direct = double.tryParse(spoken.trim().replaceAll(',', '.').replaceAll(' ', ''));
  if (direct != null) return direct;
  final words = _words(spoken);
  final point = words.indexWhere((w) => w == 'point' || w == 'dot' || w == 'decimal');
  final whole = _numberWords(point < 0 ? words : words.sublist(0, point));
  if (whole == null) return null;
  if (point < 0) return whole.toDouble();
  final fraction = spokenToDigits(words.sublist(point + 1).join(' '));
  return fraction.isEmpty ? whole.toDouble() : double.tryParse('$whole.$fraction');
}

int? _year(List<String> words) {
  if (words.isEmpty) return null;
  if (words.length == 1) return int.tryParse(words.first) ?? _numberWords(words);
  // "nineteen ninety eight" -> 19 | 98; "two thousand and five" -> 2005
  if (words.contains('thousand') || words.contains('hundred')) return _numberWords(words);
  final century = _numberWords(words.sublist(0, 1));
  final rest = _numberWords(words.sublist(1).where((w) => w != 'oh' && w != 'o').toList());
  if (century == null || rest == null) return null;
  return century * 100 + rest;
}

/// "12 March 1998", "March 12th, 1998", "the twelfth of March nineteen
/// ninety eight", "12/03/1998" (day first) or "1998-03-12".
DateTime? parseSpokenDate(String spoken) {
  final s = spoken.toLowerCase().trim();
  final iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(s);
  final dmy = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$').firstMatch(s);
  int? y, m, d;
  if (iso != null) {
    (y, m, d) = (int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
  } else if (dmy != null) {
    (y, m, d) = (int.parse(dmy[3]!), int.parse(dmy[2]!), int.parse(dmy[1]!));
  } else {
    final words = _words(s.replaceAllMapped(RegExp(r'(\d+)(st|nd|rd|th)\b'), (m) => m[1]!))
        .where((w) => w != 'the' && w != 'of' && w != 'on')
        .toList();
    final mi = words.indexWhere(_months.containsKey);
    if (mi < 0) return null;
    m = _months[words[mi]];
    final before = words.sublist(0, mi);
    final after = words.sublist(mi + 1);
    List<String> dayWords, yearWords;
    if (before.isNotEmpty) {
      dayWords = before;
      yearWords = after;
    } else {
      // "March 12 1998" / "March twelfth nineteen ninety eight": the day is
      // one token, or "twenty first" style two tokens.
      final two = after.length >= 2 && _tens.containsKey(after[0]) && (_ordinals.containsKey(after[1]) || _units.containsKey(after[1]));
      dayWords = after.take(two ? 2 : 1).toList();
      yearWords = after.skip(two ? 2 : 1).toList();
    }
    d = _day(dayWords);
    y = _year(yearWords);
  }
  if (y == null || m == null || d == null) return null;
  final date = DateTime(y, m, d);
  return date.month == m && date.day == d ? date : null;
}

int? _day(List<String> words) {
  if (words.isEmpty) return null;
  if (words.length == 1) return int.tryParse(words.first) ?? _ordinals[words.first] ?? _units[words.first];
  final tens = _tens[words[0]];
  final unit = _ordinals[words[1]] ?? _units[words[1]];
  return tens != null && unit != null ? tens + unit : null;
}

bool _has(String s, List<String> phrases) {
  final padded = ' ${_words(s).join(' ')} ';
  return phrases.any((p) => padded.contains(' $p '));
}

Gender? matchGender(String spoken) {
  if (_has(spoken, ['prefer not', 'rather not', 'not say', "don't want"])) return Gender.preferNotToSay;
  if (_has(spoken, ['female', 'woman', 'girl', 'lady'])) return Gender.female;
  if (_has(spoken, ['male', 'man', 'boy', 'gentleman'])) return Gender.male;
  if (_has(spoken, ['other', 'non binary', 'nonbinary'])) return Gender.other;
  return null;
}

EyesightLevel? matchEyesight(String spoken) {
  if (_has(spoken, ['prefer not', 'rather not', 'not say'])) return EyesightLevel.preferNotToSay;
  if (_has(spoken, ['no light', 'totally', 'total', 'completely', 'fully blind', 'complete'])) {
    return EyesightLevel.total;
  }
  if (_has(spoken, ['light perception', 'light only', 'light and dark', 'only light'])) {
    return EyesightLevel.lightPerception;
  }
  if (_has(spoken, ['blind'])) return EyesightLevel.blind;
  if (_has(spoken, ['severe', 'severely', 'very low', 'very poor'])) return EyesightLevel.severe;
  if (_has(spoken, ['moderate', 'moderately', 'low vision', 'partial', 'partially'])) return EyesightLevel.moderate;
  if (_has(spoken, ['mild', 'mildly', 'slight', 'slightly'])) return EyesightLevel.mild;
  if (_has(spoken, ['none', 'no impairment', 'normal', 'good', 'fine', 'perfect', 'no problem'])) {
    return EyesightLevel.none;
  }
  return null;
}

bool? matchYesNo(String spoken) {
  // Negatives first: "not the same" contains "same".
  if (_has(spoken, ['no', 'nope', 'not', 'different'])) return false;
  if (_has(spoken, ['yes', 'yeah', 'yep', 'same', 'correct', 'right', 'sure', 'ok', 'okay'])) return true;
  return null;
}

/// Words that steer the guided voice form instead of filling a field.
enum FormVoiceControl { skip, back, stop, repeat }

FormVoiceControl? matchFormControl(String spoken) {
  final s = _words(spoken).join(' ');
  return switch (s) {
    'skip' || 'next' || 'skip this' || 'next field' || 'leave blank' || 'leave it blank' => FormVoiceControl.skip,
    'back' || 'go back' || 'previous' || 'previous field' => FormVoiceControl.back,
    'stop' || 'cancel' || 'finish' || 'done' || 'stop filling' => FormVoiceControl.stop,
    'repeat' || 'again' || 'say again' || 'pardon' || 'what' => FormVoiceControl.repeat,
    _ => null,
  };
}
