import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/app_dependencies.dart';
import '../../core/voice/form_speech.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/labelled_button.dart';
import '../../shared/widgets/voice_text_field.dart';
import 'auth_actions.dart';

/// Sign in with email and password or Google. Also the first screen on a
/// new install, where the user can continue as a guest.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _status;
  bool _isError = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _say(String text, {bool error = true}) async {
    setState(() {
      _status = text;
      _isError = error;
    });
    await AppScope.of(context).guidance.announce(text, remember: false);
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      await _say('Enter your email and password.');
      return;
    }
    setState(() => _busy = true);
    try {
      final session = await AppScope.of(context).auth.login(email, _password.text);
      if (mounted) await onSignedIn(context, session);
    } on ApiException catch (e) {
      if (mounted) await _say(e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() => _busy = true);
    final error = await continueWithGoogle(context);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) await _say(error);
  }

  Future<void> _guest() async {
    final deps = AppScope.of(context);
    await deps.auth.markWelcomeDone();
    if (!mounted) return;
    context.go('/');
    await deps.guidance.announce(
        'Continuing as a guest. You can sign in later from My Profile.', remember: false);
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = AppScope.of(context).auth.isSignedIn;
    return AppScaffold(
      title: 'Log in',
      children: [
        Text('Welcome to SmartSight', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text(
          'Sign in to keep your profile and personal items in your account. '
          'You can type, or use the microphone buttons to speak.',
          style: TextStyle(fontSize: 18),
        ),
        StatusText(_status, isError: _isError),
        if (signedIn)
          const StatusText('You are already signed in. Signing in again switches account.'),
        AutofillGroup(
          child: Column(children: [
            VoiceTextField(
              key: const Key('login-email-field'),
              controller: _email,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              fromSpeech: spokenToEmail,
            ),
            VoiceTextField(
              key: const Key('login-password-field'),
              controller: _password,
              label: 'Password',
              obscure: true,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _login(),
              fromSpeech: spokenToPassword,
            ),
          ]),
        ),
        const SizedBox(height: 8),
        LabelledButton(
          key: const Key('login-button'),
          icon: Icons.login,
          label: _busy ? 'Signing in…' : 'Log in',
          onPressed: _busy ? null : _login,
        ),
        const SizedBox(height: 12),
        GoogleButton(onPressed: _busy ? null : _google),
        const SectionHeading('New to SmartSight?'),
        LabelledButton(
          key: const Key('go-register-button'),
          icon: Icons.person_add_alt_1,
          label: 'Create an account',
          primary: false,
          onPressed: () => context.go('/register'),
        ),
        const SizedBox(height: 12),
        LabelledButton(
          key: const Key('guest-button'),
          icon: Icons.arrow_forward,
          label: 'Continue as guest',
          primary: false,
          semanticHint: 'Use SmartSight without an account. Items are kept on this phone only.',
          onPressed: _guest,
        ),
      ],
    );
  }
}
