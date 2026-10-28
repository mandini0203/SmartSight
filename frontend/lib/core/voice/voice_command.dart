/// Screens reachable by voice or touch.
enum AppDestination {
  home('/', 'Home'),
  scan('/scan', 'Smart Scan'),
  items('/items', 'My Items'),
  doorsSigns('/doors-signs', 'Doors and Signs'),
  colour('/colour', 'Colour Finder'),
  settings('/settings', 'Settings'),
  profile('/profile', 'My Profile'),
  login('/login', 'Log in'),
  register('/register', 'Create account');

  const AppDestination(this.path, this.title);
  final String path;
  final String title;
}

/// Guidance / scanning controls.
enum ControlAction { start, pause, resume, stop, repeat, capture }

sealed class VoiceCommand {
  const VoiceCommand();
}

class NavigateCommand extends VoiceCommand {
  const NavigateCommand(this.destination);
  final AppDestination destination;

  @override
  bool operator ==(Object other) => other is NavigateCommand && other.destination == destination;
  @override
  int get hashCode => destination.hashCode;
  @override
  String toString() => 'Navigate(${destination.name})';
}

class BackCommand extends VoiceCommand {
  const BackCommand();
  @override
  bool operator ==(Object other) => other is BackCommand;
  @override
  int get hashCode => 1;
  @override
  String toString() => 'Back';
}

class ControlCommand extends VoiceCommand {
  const ControlCommand(this.action);
  final ControlAction action;

  @override
  bool operator ==(Object other) => other is ControlCommand && other.action == action;
  @override
  int get hashCode => action.hashCode;
  @override
  String toString() => 'Control(${action.name})';
}

class SignOutCommand extends VoiceCommand {
  const SignOutCommand();
  @override
  bool operator ==(Object other) => other is SignOutCommand;
  @override
  int get hashCode => 3;
  @override
  String toString() => 'SignOut';
}

/// "voice on" / "voice off": switches the app's spoken output.
class VoiceToggleCommand extends VoiceCommand {
  const VoiceToggleCommand({required this.on});
  final bool on;

  @override
  bool operator ==(Object other) => other is VoiceToggleCommand && other.on == on;
  @override
  int get hashCode => Object.hash(4, on);
  @override
  String toString() => 'Voice(${on ? 'on' : 'off'})';
}

class HelpCommand extends VoiceCommand {
  const HelpCommand();
  @override
  bool operator ==(Object other) => other is HelpCommand;
  @override
  int get hashCode => 2;
  @override
  String toString() => 'Help';
}

/// Result of interpreting one utterance.
class CommandMatch {
  const CommandMatch({required this.command, required this.normalisedText, required this.matchedPhrase});
  final VoiceCommand command;
  final String normalisedText;
  final String matchedPhrase;
}
