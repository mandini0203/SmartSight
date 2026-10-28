import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/app_dependencies.dart';
import '../../shared/voice_form_filler.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/labelled_button.dart';
import 'auth_actions.dart';
import 'profile_form.dart';

/// Create an account with email, password and profile details, or with Google.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = ProfileFormController(includeAccount: true);
  late final VoiceFormFiller _voice = VoiceFormFiller(AppScope.of(context));
  bool _busy = false;
  String? _status;
  bool _isError = true;

  @override
  void dispose() {
    _voice.stop();
    _voice.dispose();
    _form.dispose();
    super.dispose();
  }

  Future<void> _say(String text, {bool error = true}) async {
    setState(() {
      _status = text;
      _isError = error;
    });
    await AppScope.of(context).guidance.announce(text, remember: false);
  }

  Future<void> _fillByVoice() async {
    if (_voice.running.value) {
      _voice.stop();
      return;
    }
    await _voice.run(
      _form.voiceSteps(),
      intro: "Let's fill in the registration form. I'll ask one question at a time.",
      outro: 'All done. Check the form, then press Create account at the bottom.',
    );
  }

  Future<void> _submit() async {
    final errors = _form.validate();
    if (errors.isNotEmpty) {
      await _say('Please fix ${errors.length == 1 ? 'one field' : '${errors.length} fields'}. ${errors.first}');
      return;
    }
    setState(() => _busy = true);
    try {
      final session = await AppScope.of(context).auth.register(
            email: _form.email.text,
            password: _form.password.text,
            profile: _form.toDraft(),
          );
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

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Create account',
      children: [
        const Text(
          'Create your SmartSight account. Your birthday, age and gender are filled in from your NIC number.',
          style: TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<bool>(
          valueListenable: _voice.running,
          builder: (context, running, _) => LabelledButton(
            key: const Key('voice-fill-button'),
            icon: running ? Icons.stop_circle_outlined : Icons.record_voice_over,
            label: running ? 'Stop filling by voice' : 'Fill the form by voice',
            semanticHint: 'SmartSight asks each question and fills in your answers',
            onPressed: _fillByVoice,
          ),
        ),
        const SizedBox(height: 12),
        GoogleButton(onPressed: _busy ? null : _google),
        const SizedBox(height: 4),
        const Text('Or register with your email address:', style: TextStyle(fontSize: 16)),
        AutofillGroup(child: ProfileForm(controller: _form)),
        StatusText(_status, isError: _isError),
        const SizedBox(height: 8),
        LabelledButton(
          key: const Key('create-account-button'),
          icon: Icons.person_add_alt_1,
          label: _busy ? 'Creating account…' : 'Create account',
          onPressed: _busy ? null : _submit,
        ),
        const SizedBox(height: 12),
        LabelledButton(
          icon: Icons.login,
          label: 'I already have an account',
          primary: false,
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }
}
