import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/app_dependencies.dart';
import '../../core/auth/google_auth.dart';
import '../../core/auth/profile.dart';
import '../../core/feedback/haptics.dart';
import '../../shared/widgets/labelled_button.dart';

/// Signs in with Google, then goes home, or to "Complete your profile" for a
/// new account. Returns a message to show when it did not succeed.
Future<String?> continueWithGoogle(BuildContext context) async {
  final deps = AppScope.of(context);
  try {
    final session = await deps.auth.signInWithGoogle();
    if (session == null) return 'Google sign-in was cancelled.';
    if (context.mounted) await onSignedIn(context, session);
    return null;
  } on GoogleAuthException catch (e) {
    return e.userMessage;
  } on ApiException catch (e) {
    return e.userMessage;
  }
}

/// Announces the result of a successful sign-in or registration and leaves
/// the sign-in screens.
Future<void> onSignedIn(BuildContext context, AuthSession session) async {
  final deps = AppScope.of(context);
  final name = session.user.firstName;
  context.go(session.user.profileComplete ? '/' : '/complete-profile');
  await deps.haptics.play(HapticCue.success);
  if (!session.user.profileComplete) {
    await deps.guidance.announce(
        'Signed in with Google. Please complete your profile to finish creating your account.', remember: false);
    return;
  }
  await deps.guidance.announce(
      session.isNewUser ? 'Welcome, $name. Your account has been created.' : 'Welcome back, $name.',
      remember: false);
}

class GoogleButton extends StatelessWidget {
  const GoogleButton({super.key, required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => LabelledButton(
        key: const Key('google-sign-in-button'),
        icon: Icons.g_mobiledata,
        label: 'Continue with Google',
        primary: false,
        semanticHint: 'Choose your Google account',
        onPressed: onPressed,
      );
}

/// Spoken and visible status line for the account screens.
class StatusText extends StatelessWidget {
  const StatusText(this.text, {super.key, this.isError = false});
  final String? text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isError ? scheme.errorContainer : scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(text!,
              style: TextStyle(fontSize: 18, color: isError ? scheme.onErrorContainer : scheme.onSecondaryContainer)),
        ),
      ),
    );
  }
}
