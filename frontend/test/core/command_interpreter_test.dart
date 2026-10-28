import 'package:flutter_test/flutter_test.dart';
import 'package:smartsight/core/voice/command_interpreter.dart';
import 'package:smartsight/core/voice/voice_command.dart';

void main() {
  final interpreter = CommandInterpreter();

  group('every alias maps to its command', () {
    for (final entry in CommandInterpreter.aliases.entries) {
      for (final phrase in entry.value) {
        test('"$phrase" -> ${entry.key}', () {
          expect(interpreter.interpret(phrase)?.command, entry.key);
        });
      }
    }
  });

  group('navigation verbs', () {
    const cases = {
      'go to smart scan': AppDestination.scan,
      'open my items': AppDestination.items,
      'take me to the colour finder': AppDestination.colour,
      'show me doors and signs': AppDestination.doorsSigns,
      'navigate to settings': AppDestination.settings,
      'go to the dashboard': AppDestination.home,
      'open scan': AppDestination.scan,
      'open the color finder': AppDestination.colour,
      'switch to personal items': AppDestination.items,
    };
    cases.forEach((text, dest) {
      test(text, () => expect(interpreter.interpret(text)?.command, NavigateCommand(dest)));
    });
  });

  group('normalisation', () {
    const cases = {
      'Hey SmartSight, PAUSE!': ControlAction.pause,
      '  resume scanning please ': ControlAction.resume,
      'Stop.': ControlAction.stop,
      'Say that again?': ControlAction.repeat,
      'Could you start scanning': ControlAction.start,
      'analyze now': ControlAction.capture,
    };
    cases.forEach((text, action) {
      test(text, () => expect(interpreter.interpret(text)?.command, ControlCommand(action)));
    });

    test('US spelling of colour', () {
      expect(interpreter.interpret('Color Finder')?.command, const NavigateCommand(AppDestination.colour));
    });
  });

  group('not app commands (left for the task-intent resolver)', () {
    for (final text in [
      'find my phone',
      'where is the exit',
      'find a place to sit',
      'what colour is this',
      'describe my surroundings',
      'the bus stop is near',
      'open stop',
      'stop the bus',
      '',
      '   ',
      '???',
    ]) {
      test('"$text"', () => expect(interpreter.interpret(text), isNull));
    }
  });

  test('is deterministic', () {
    for (var i = 0; i < 3; i++) {
      expect(interpreter.interpret('pause')?.command, const ControlCommand(ControlAction.pause));
    }
  });

  test('reports the normalised text and matched phrase', () {
    final m = interpreter.interpret('Please go to Smart Scan!')!;
    expect(m.normalisedText, 'go to smart scan');
    expect(m.matchedPhrase, 'smart scan');
  });
}
