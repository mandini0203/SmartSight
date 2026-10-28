import 'voice_command.dart';

/// Deterministic interpreter for in-app voice commands.
///
/// 1. Normalise the recognised text (lower case, strip punctuation, drop the
///    wake word and politeness words, unify spelling variants).
/// 2. Strip one leading navigation verb ("go to", "open", ...).
/// 3. Look the remainder up in a fixed alias table. The whole utterance must
///    match, so "the bus stop" never triggers Stop.
///
/// Anything that does not match is not an app command. The caller can send it
/// to the backend task-intent resolver (for example "find my phone").
class CommandInterpreter {
  CommandInterpreter() {
    for (final entry in _aliases.entries) {
      for (final phrase in entry.value) {
        final key = normalise(phrase);
        assert(!_lookup.containsKey(key), 'Duplicate alias "$key"');
        _lookup[key] = entry.key;
      }
    }
  }

  final Map<String, VoiceCommand> _lookup = {};

  static const _navVerbs = [
    'take me to the', 'take me to', 'navigate to', 'switch to', 'go to the', 'go to', 'open the', 'open',
    'show me the', 'show me', 'show the', 'show', 'launch', 'start the', 'bring up',
  ];

  static const _fillers = [
    'hey smartsight', 'ok smartsight', 'okay smartsight', 'smartsight', 'please', 'could you', 'can you',
    'would you', 'thanks', 'thank you',
  ];

  static final Map<VoiceCommand, List<String>> _aliases = {
    const NavigateCommand(AppDestination.home): [
      'home', 'home screen', 'dashboard', 'main menu', 'menu', 'main screen', 'return to the dashboard',
      'return to dashboard', 'go home', 'back to home', 'back to the dashboard', 'back to dashboard',
    ],
    const NavigateCommand(AppDestination.scan): [
      'smart scan', 'scan screen', 'smart environment scan', 'environment scan', 'scanner', 'smart scanner',
    ],
    const NavigateCommand(AppDestination.items): [
      'my items', 'items', 'personal items', 'my personal items', 'my things', 'my belongings', 'belongings',
    ],
    const NavigateCommand(AppDestination.doorsSigns): [
      'doors and signs', 'doors', 'signs', 'doors and signs assistant', 'door and sign', 'doors signs',
      'signs and doors', 'exit finder',
    ],
    const NavigateCommand(AppDestination.colour): [
      'colour finder', 'colour', 'colours', 'colour identifier', 'colour detector', 'colour screen',
    ],
    const NavigateCommand(AppDestination.settings): ['settings', 'preferences', 'options', 'setup'],
    const NavigateCommand(AppDestination.profile): [
      'my profile', 'profile', 'my account', 'account', 'my details', 'account details',
    ],
    const NavigateCommand(AppDestination.login): ['log in', 'login', 'sign in', 'signin', 'log me in'],
    const NavigateCommand(AppDestination.register): [
      'register', 'sign up', 'signup', 'create account', 'create an account', 'new account', 'registration',
    ],
    const SignOutCommand(): ['sign out', 'log out', 'logout', 'sign me out', 'log me out'],
    const BackCommand(): ['back', 'go back', 'previous screen', 'previous'],
    const ControlCommand(ControlAction.start): [
      'start', 'start scanning', 'start scan', 'begin', 'begin scanning', 'start guidance', 'go',
      'continuous scan', 'keep scanning',
    ],
    const ControlCommand(ControlAction.pause): [
      'pause', 'pause scanning', 'pause guidance', 'hold on', 'wait', 'hold',
    ],
    const ControlCommand(ControlAction.resume): [
      'resume', 'resume scanning', 'resume guidance', 'continue', 'continue scanning', 'carry on', 'unpause',
    ],
    const ControlCommand(ControlAction.stop): [
      'stop', 'stop scanning', 'stop guidance', 'cancel', 'end', 'finish', 'quiet', 'be quiet', 'shut up',
    ],
    const ControlCommand(ControlAction.repeat): [
      'repeat', 'say again', 'say that again', 'repeat that', 'what did you say', 'pardon', 'again',
      'repeat guidance', 'repeat last',
    ],
    const ControlCommand(ControlAction.capture): [
      'capture', 'take a picture', 'take picture', 'take a photo', 'take photo', 'analyse', 'analyse now',
      'check', 'look', 'snap', 'scan', 'scan now', 'capture frame', 'what is this',
    ],
    const VoiceToggleCommand(on: true): [
      'voice on', 'turn voice on', 'turn on voice', 'turn the voice on', 'turn on the voice', 'switch voice on',
      'switch on voice', 'enable voice', 'unmute', 'sound on', 'speak to me', 'talk to me',
    ],
    const VoiceToggleCommand(on: false): [
      'voice off', 'turn voice off', 'turn off voice', 'turn the voice off', 'turn off the voice',
      'switch voice off', 'switch off voice', 'disable voice', 'mute', 'sound off', 'stop talking', 'silent mode',
    ],
    const HelpCommand(): ['help', 'commands', 'what can i say', 'list commands', 'voice commands'],
  };

  /// All phrases, for help screens and tests.
  static Map<VoiceCommand, List<String>> get aliases => _aliases;

  static String normalise(String text) {
    var t = text.toLowerCase().replaceAll('’', "'");
    t = t.replaceAll(RegExp(r'\bcolor\b'), 'colour').replaceAll(RegExp(r'\bcolors\b'), 'colours');
    t = t.replaceAll(RegExp(r'\banalyze\b'), 'analyse');
    t = t.replaceAll('&', ' and ');
    t = t.replaceAll(RegExp(r"[^a-z0-9' ]+"), ' ').replaceAll("'", '');
    for (final f in _fillers) {
      t = t.replaceAll(RegExp('\\b${RegExp.escape(f)}\\b'), ' ');
    }
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  CommandMatch? interpret(String recognised) {
    final text = normalise(recognised);
    if (text.isEmpty) return null;

    final direct = _lookup[text];
    if (direct != null) return CommandMatch(command: direct, normalisedText: text, matchedPhrase: text);

    for (final verb in _navVerbs) {
      if (text.startsWith('$verb ')) {
        final rest = text.substring(verb.length + 1);
        final cmd = rest == 'scan' ? const NavigateCommand(AppDestination.scan) : _lookup[rest];
        // Only screens can follow a navigation verb ("open stop" is not a command).
        if (cmd is NavigateCommand) {
          return CommandMatch(command: cmd, normalisedText: text, matchedPhrase: rest);
        }
      }
    }
    return null;
  }
}
