import 'package:flutter_test/flutter_test.dart';
import 'package:smartsight/core/auth/profile.dart';
import 'package:smartsight/core/voice/form_speech.dart';

void main() {
  test('email', () {
    expect(spokenToEmail('john dot perera at gmail dot com'), 'john.perera@gmail.com');
    expect(spokenToEmail('Nimal underscore 98 at the rate yahoo dot co dot uk'), 'nimal_98@yahoo.co.uk');
    expect(spokenToEmail('asha.silva@gmail.com'), 'asha.silva@gmail.com');
    expect(spokenToEmail('kamal dash p at outlook dot com'), 'kamal-p@outlook.com');
  });

  test('digits, phone and postal code', () {
    expect(spokenToDigits('zero seven seven one two three four five six seven'), '0771234567');
    expect(spokenToDigits('double seven one'), '771');
    expect(spokenToDigits('077 123 4567'), '0771234567');
    expect(spokenToPhone('plus nine four seven seven one two three four five six seven'), '+94771234567');
    expect(spokenToPhone('+94 77 123 4567'), '+94771234567');
    expect(spokenToPostalCode('one oh one one five'), '10115');
  });

  test('NIC', () {
    expect(spokenToNic('nine eight one two three four five six seven v'), '981234567V');
    expect(spokenToNic('981234567v'), '981234567V');
    expect(spokenToNic('9 8 1 2 3 4 5 6 7 X'), '981234567X');
    expect(spokenToNic('199812345678'), '199812345678');
    expect(spokenToNic('one nine nine eight one two three four five six seven eight'), '199812345678');
  });

  test('names and text', () {
    expect(spokenToName('nimal PERERA'), 'Nimal Perera');
    expect(spokenToName("o'neil"), "O'neil");
    expect(spokenToText('12  galle road'), '12 galle road');
    expect(spokenToText('galle road'), 'Galle road');
    expect(spokenToPassword('secret 12 34'), 'secret1234');
  });

  test('numbers', () {
    expect(spokenToNumber('22.5'), 22.5);
    expect(spokenToNumber('twenty two point five'), 22.5);
    expect(spokenToNumber('thirty'), 30);
    expect(spokenToNumber('banana'), isNull);
  });

  test('dates', () {
    expect(parseSpokenDate('12 March 1998'), DateTime(1998, 3, 12));
    expect(parseSpokenDate('March 12th, 1998'), DateTime(1998, 3, 12));
    expect(parseSpokenDate('the twelfth of March nineteen ninety eight'), DateTime(1998, 3, 12));
    expect(parseSpokenDate('twenty first of June two thousand and five'), DateTime(2005, 6, 21));
    expect(parseSpokenDate('12/03/1998'), DateTime(1998, 3, 12));
    expect(parseSpokenDate('1998-03-12'), DateTime(1998, 3, 12));
    expect(parseSpokenDate('30 February 1998'), isNull);
    expect(parseSpokenDate('next tuesday'), isNull);
  });

  test('choices', () {
    expect(matchGender('I am a woman'), Gender.female);
    expect(matchGender('male'), Gender.male);
    expect(matchGender('female'), Gender.female);
    expect(matchGender("I'd prefer not to say"), Gender.preferNotToSay);
    expect(matchEyesight('totally blind'), EyesightLevel.total);
    expect(matchEyesight('I can only see light and dark'), EyesightLevel.lightPerception);
    expect(matchEyesight('blind'), EyesightLevel.blind);
    expect(matchEyesight('severe'), EyesightLevel.severe);
    expect(matchEyesight('partially sighted'), EyesightLevel.moderate);
    expect(matchEyesight('no impairment'), EyesightLevel.none);
    expect(matchYesNo('yes it is'), isTrue);
    expect(matchYesNo('same'), isTrue);
    expect(matchYesNo('no, it is different'), isFalse);
    expect(matchYesNo('not the same'), isFalse);
  });

  test('form controls need the whole utterance', () {
    expect(matchFormControl('skip'), FormVoiceControl.skip);
    expect(matchFormControl('Go back'), FormVoiceControl.back);
    expect(matchFormControl('stop'), FormVoiceControl.stop);
    expect(matchFormControl('12 back road'), isNull);
  });
}
