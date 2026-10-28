import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import '../features/account/edit_profile_screen.dart';
import '../features/account/login_screen.dart';
import '../features/account/profile_screen.dart';
import '../features/account/register_screen.dart';
import '../features/colour/colour_screen.dart';
import '../features/doors_signs/doors_signs_screen.dart';
import '../features/home/home_screen.dart';
import '../features/items/find_item_screen.dart';
import '../features/items/items_screen.dart';
import '../features/items/register_item_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/settings/settings_screen.dart';

bool _flag(GoRouterState s, String name) => s.uri.queryParameters[name] == '1';

/// Every destination is nested under home so system Back returns there.
///
/// A new Google account is sent to "Complete your profile" until its
/// details are saved.
GoRouter buildRouter({required AuthController auth, String initialLocation = '/'}) => GoRouter(
      initialLocation: initialLocation,
      refreshListenable: auth,
      redirect: (context, state) {
        const complete = '/complete-profile';
        if (auth.needsProfile && state.matchedLocation != complete) return complete;
        if (!auth.needsProfile && state.matchedLocation == complete) return '/';
        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HomeScreen(),
          routes: [
            GoRoute(
              path: 'scan',
              builder: (context, state) => ScanScreen(
                key: ValueKey(state.uri.toString()),
                initialTask: ScanTask.fromName(state.uri.queryParameters['task']),
                initialTarget: state.uri.queryParameters['target'],
                autostart: _flag(state, 'autostart'),
              ),
            ),
            GoRoute(
              path: 'items',
              builder: (context, state) => const ItemsScreen(),
              routes: [
                GoRoute(path: 'register', builder: (context, state) => const RegisterItemScreen()),
                GoRoute(
                  path: 'find/:id',
                  builder: (context, state) => FindItemScreen(
                    itemId: state.pathParameters['id']!,
                    autostart: _flag(state, 'autostart'),
                  ),
                ),
              ],
            ),
            GoRoute(
              path: 'doors-signs',
              builder: (context, state) => DoorsSignsScreen(autostart: _flag(state, 'autostart')),
            ),
            GoRoute(
              path: 'colour',
              builder: (context, state) => ColourScreen(autostart: _flag(state, 'autostart')),
            ),
            GoRoute(path: 'settings', builder: (context, state) => const SettingsScreen()),
            GoRoute(path: 'login', builder: (context, state) => const LoginScreen()),
            GoRoute(path: 'register', builder: (context, state) => const RegisterScreen()),
            GoRoute(
              path: 'profile',
              builder: (context, state) => const ProfileScreen(),
              routes: [GoRoute(path: 'edit', builder: (context, state) => const EditProfileScreen())],
            ),
            GoRoute(
              path: 'complete-profile',
              builder: (context, state) => const EditProfileScreen(completing: true),
            ),
          ],
        ),
      ],
    );
