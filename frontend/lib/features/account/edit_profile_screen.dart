import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/app_dependencies.dart';
import '../../core/feedback/haptics.dart';
import '../../shared/voice_form_filler.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/labelled_button.dart';
import 'auth_actions.dart';
import 'profile_form.dart';

/// Edits the profile, or (with [completing]) asks a new Google user for the
/// details Google does not provide.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, this.completing = false});

  final bool completing;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final ProfileFormController _form =
      ProfileFormController(includeAccount: false, initial: AppScope.of(context).auth.user);
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
      intro: "I'll ask for each of your details in turn.",
      outro: 'All done. Check the form, then press Save at the bottom.',
    );
  }

  Future<void> _save() async {
    final deps = AppScope.of(context);
    final errors = _form.validate();
    if (errors.isNotEmpty) {
      await _say('Please fix ${errors.length == 1 ? 'one field' : '${errors.length} fields'}. ${errors.first}');
      return;
    }
    setState(() => _busy = true);
    try {
      final user = await deps.auth.updateProfile(_form.toDraft());
      await deps.haptics.play(HapticCue.success);
      if (!mounted) return;
      context.go(widget.completing ? '/' : '/profile');
      await deps.guidance.announce(
          widget.completing ? 'Thank you, ${user.firstName}. Your account is ready.' : 'Profile saved.',
          remember: false);
    } on ApiException catch (e) {
      if (mounted) await _say(e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final deps = AppScope.of(context);
    await deps.auth.signOut();
    if (!mounted) return;
    context.go('/login');
    await deps.guidance.announce('Signed out.', remember: false);
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).auth.user;
    return AppScaffold(
      title: widget.completing ? 'Complete your profile' : 'Edit profile',
      children: [
        if (widget.completing)
          Text(
            'Welcome${user == null || user.firstName.isEmpty ? '' : ', ${user.firstName}'}. '
            'Please add a few details to finish creating your account.',
            style: const TextStyle(fontSize: 18),
          ),
        if (user != null) Text('Signed in as ${user.email}', style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        ValueListenableBuilder<bool>(
          valueListenable: _voice.running,
          builder: (context, running, _) => LabelledButton(
            key: const Key('voice-fill-button'),
            icon: running ? Icons.stop_circle_outlined : Icons.record_voice_over,
            label: running ? 'Stop filling by voice' : 'Fill the form by voice',
            onPressed: _fillByVoice,
          ),
        ),
        ProfileForm(controller: _form),
        StatusText(_status, isError: _isError),
        const SizedBox(height: 8),
        LabelledButton(
          key: const Key('save-profile-button'),
          icon: Icons.save,
          label: _busy ? 'Saving…' : (widget.completing ? 'Save and continue' : 'Save'),
          onPressed: _busy ? null : _save,
        ),
        if (widget.completing) ...[
          const SizedBox(height: 12),
          LabelledButton(icon: Icons.logout, label: 'Sign out', primary: false, onPressed: _signOut),
        ],
      ],
    );
  }
}
