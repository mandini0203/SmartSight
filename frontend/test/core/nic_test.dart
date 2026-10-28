import 'package:flutter_test/flutter_test.dart';
import 'package:smartsight/core/auth/nic.dart';

/// Same cases as backend/tests/test_nic.py, so both sides agree.
void main() {
  final today = DateTime(2026, 10, 23);

  const valid = {
    '199800100123': (1998, 1, 1, NicGender.male, false),
    '981234567V': (1998, 5, 2, NicGender.male, true),
    '986234567v': (1998, 5, 2, NicGender.female, true),
    '200005901234': (2000, 2, 28, NicGender.male, false),
    '200006000000': (2000, 2, 29, NicGender.male, false),
    '200206101234': (2002, 3, 1, NicGender.male, false),
    '19968660 1234': (1996, 12, 31, NicGender.female, false),
    '853660000X': (1985, 12, 31, NicGender.male, true),
  };
  valid.forEach((nic, expected) {
    test('decodes $nic', () {
      final r = decodeNic(nic, today: today);
      expect(r.error, isNull);
      final (y, m, d, gender, old) = expected;
      expect(r.info!.birthday, DateTime(y, m, d));
      expect(r.info!.gender, gender);
      expect(r.info!.isOldFormat, old);
      expect(r.info!.nic, isNot(contains(' ')));
    });
  });

  for (final nic in [
    '', '12345', '98123456V7', '981234567A', '19981234567', '1998123456789', '980004567V', '983674567V',
    '985004567V', '200206001234', '300012301234',
  ]) {
    test('rejects "$nic"', () {
      final r = decodeNic(nic, today: today);
      expect(r.isValid, isFalse);
      expect(r.error, isNotEmpty);
    });
  }

  test('age', () {
    expect(ageOn(DateTime(1998, 10, 23), today: today), 28);
    expect(ageOn(DateTime(1998, 10, 24), today: today), 27);
  });
}
