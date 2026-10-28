import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/app_dependencies.dart';
import '../../core/auth/profile.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/labelled_button.dart';
import 'auth_actions.dart';
import 'profile_form.dart';

/// The signed-in user's profile, or sign-in options for a guest.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _status;
  bool _busy = false;

  Future<void> _say(String text) async {
    setState(() => _status = text);
    await AppScope.of(context).guidance.announce(text, remember: false);
  }

  Future<void> _google() async {
    setState(() => _busy = true);
    final error = await continueWithGoogle(context);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) await _say(error);
  }

  Future<void> _signOut() async {
    final deps = AppScope.of(context);
    await deps.auth.signOut();
    if (!mounted) return;
    await deps.guidance.announce(
        'Signed out. You are now using SmartSight as a guest.', remember: false);
  }

  Future<void> _delete() async {
    final deps = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
            'Your profile and the items saved in your account are deleted from the server. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete account')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final id = deps.auth.user?.id;
    try {
      await deps.auth.deleteAccount();
      if (id != null) await deps.items.deleteAccountData(id);
      await deps.guidance.announce('Your account has been deleted.', remember: false);
    } on ApiException catch (e) {
      await _say(e.userMessage);
    }
  }

  static String _summary(UserProfile u) {
    final parts = [
      'You are signed in as ${u.fullName}, ${u.email}.',
      if (u.age != null) 'Age ${u.age}.',
      if (u.eyesight != null) 'Eyesight: ${u.eyesight!.label}.',
      if (u.mobile != null) 'Mobile ${u.mobile!.split('').join(' ')}.',
    ];
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    return ListenableBuilder(
      listenable: deps.auth,
      builder: (context, _) {
        final u = deps.auth.user;
        return AppScaffold(
          title: 'My Profile',
          children: u == null ? _guest(context) : _signedIn(context, u),
        );
      },
    );
  }

  List<Widget> _guest(BuildContext context) => [
        const Text(
          'You are using SmartSight as a guest. Your items are kept on this phone only.\n\n'
          'Sign in or create an account to keep your profile and items in your account, '
          'and use them on another phone.',
          style: TextStyle(fontSize: 18),
        ),
        StatusText(_status, isError: true),
        const SizedBox(height: 12),
        LabelledButton(
          key: const Key('profile-login-button'),
          icon: Icons.login,
          label: 'Log in',
          onPressed: () => context.go('/login'),
        ),
        const SizedBox(height: 12),
        LabelledButton(
          key: const Key('profile-register-button'),
          icon: Icons.person_add_alt_1,
          label: 'Create an account',
          primary: false,
          onPressed: () => context.go('/register'),
        ),
        const SizedBox(height: 12),
        GoogleButton(onPressed: _busy ? null : _google),
      ];

  List<Widget> _signedIn(BuildContext context, UserProfile u) {
    final address = [u.addressLine1, u.addressLine2, u.addressLine3].whereType<String>().join(', ');
    final rows = <(String, String?)>[
      ('Name', u.fullName),
      ('Email', u.email),
      ('Sign-in', [if (u.hasPassword) 'Email and password', if (u.googleLinked) 'Google'].join(', ')),
      ('NIC', u.nic),
      ('Birthday', u.birthday == null ? null : '${formatDate(u.birthday!)} (age ${u.age})'),
      ('Gender', u.gender?.label),
      ('Address', address.isEmpty ? null : address),
      ('Postal code', u.postalCode),
      ('Mobile', u.mobile),
      ('WhatsApp', u.whatsappSameAsMobile ? 'Same as mobile' : u.whatsapp),
      ('BMI', u.bmi?.toStringAsFixed(1)),
      ('Eyesight', u.eyesight?.label),
    ];
    return [
      Text('Hello, ${u.firstName}', style: Theme.of(context).textTheme.headlineSmall),
      StatusText(_status, isError: true),
      const SizedBox(height: 8),
      LabelledButton(
        key: const Key('read-profile-button'),
        icon: Icons.volume_up,
        label: 'Read my profile aloud',
        onPressed: () => AppScope.of(context).guidance.announce(_summary(u), remember: false),
      ),
      const SectionHeading('Your details'),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            children: [
              for (final (label, value) in rows)
                MergeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        Expanded(child: Text(value ?? 'Not set', style: const TextStyle(fontSize: 18))),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      LabelledButton(
        key: const Key('edit-profile-button'),
        icon: Icons.edit,
        label: 'Edit profile',
        onPressed: () => context.go('/profile/edit'),
      ),
      const SizedBox(height: 12),
      LabelledButton(
        key: const Key('sign-out-button'),
        icon: Icons.logout,
        label: 'Sign out',
        primary: false,
        onPressed: _signOut,
      ),
      const SizedBox(height: 12),
      LabelledButton(
        key: const Key('delete-account-button'),
        icon: Icons.delete_forever,
        label: 'Delete account',
        primary: false,
        onPressed: _delete,
      ),
    ];
  }
}
