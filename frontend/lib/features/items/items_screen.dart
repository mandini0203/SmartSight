import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/app_dependencies.dart';
import '../../core/storage/item_repository.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/labelled_button.dart';
import '../../shared/widgets/result_widgets.dart';

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  @override
  void initState() {
    super.initState();
    // Pick up items added on another phone; does nothing for guests.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).items.sync();
    });
  }

  Future<void> _confirmDelete(BuildContext context, PersonalItem item) async {
    final deps = AppScope.of(context);
    final signedIn = deps.auth.isSignedIn;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${item.name}?'),
        content: Text('Its reference photos will be removed from this phone${signedIn ? ' and your account' : ''}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await deps.items.delete(item.id);
      await deps.guidance.announce('${item.name} deleted.', remember: false);
    } on ApiException catch (e) {
      await deps.guidance.announce(
          e.isOffline ? 'Cannot delete ${item.name} while offline. Please try again later.' : e.userMessage,
          remember: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).items;
    final signedIn = AppScope.of(context).auth.isSignedIn;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final items = repo.items;
        return AppScaffold(
          title: 'My Items',
          children: [
            LabelledButton(
              key: const Key('register-item-button'),
              icon: Icons.add_a_photo,
              label: 'Register a new item',
              onPressed: () => context.go('/items/register'),
            ),
            SectionHeading('Registered items (${items.length})'),
            if (items.isEmpty)
              const Text(
                'No items yet. Register your phone, bag or another belonging with a few photos, '
                'and SmartSight can look for it.',
                style: TextStyle(fontSize: 18),
              ),
            for (final item in items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      Text(
                        '${kRegistrableItemTypes[item.label] ?? item.label} · '
                        '${item.referencePaths.length} reference photo${item.referencePaths.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: LabelledButton(
                            icon: Icons.search,
                            label: 'Find',
                            semanticHint: 'Search for ${item.name}',
                            onPressed: () => context.go('/items/find/${item.id}'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LabelledButton(
                            icon: Icons.delete_outline,
                            label: 'Delete',
                            primary: false,
                            semanticHint: 'Delete ${item.name}',
                            onPressed: () => _confirmDelete(context, item),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ProvenanceNote([
              'How matching works: the detector finds objects of the registered type, then each one is '
                  'compared with your reference photos using image features, colour and texture.',
              'Match thresholds have not yet been calibrated on real users\' items. Two identical-looking '
                  'items cannot be told apart.',
              signedIn
                  ? 'Your items and reference photos are saved in your account on your SmartSight server and on '
                      'this phone, so they are available when you sign in on another phone.'
                  : 'You are using SmartSight as a guest: reference photos are stored only on this phone and sent '
                      'to your SmartSight server only while searching. Sign in to keep them in your account.',
            ]),
          ],
        );
      },
    );
  }
}
