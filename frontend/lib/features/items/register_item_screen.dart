import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/app_dependencies.dart';
import '../../core/camera/frame_source.dart';
import '../../core/storage/item_repository.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/camera_panel.dart';
import '../../shared/widgets/labelled_button.dart';

const int kMaxReferencePhotos = 5;

class _Photo {
  _Photo(this.bytes, this.note, this.accepted);
  final Uint8List bytes;
  final String note;
  final bool? accepted; // null = could not be checked
}

/// Registration workflow: name, item type, then 1-5 reference photos, each
/// checked by the backend (item visible, sharp, well lit) before saving.
class RegisterItemScreen extends StatefulWidget {
  const RegisterItemScreen({super.key});

  @override
  State<RegisterItemScreen> createState() => _RegisterItemScreenState();
}

class _RegisterItemScreenState extends State<RegisterItemScreen> {
  final _name = TextEditingController();
  String _label = kRegistrableItemTypes.keys.first;
  final List<_Photo> _photos = [];
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final deps = AppScope.of(context);
    if (_photos.length >= kMaxReferencePhotos) {
      _say('You already have $kMaxReferencePhotos photos, the maximum.');
      return;
    }
    setState(() => _busy = true);
    try {
      final CapturedFrame frame = await deps.frames.capture();
      _Photo photo;
      try {
        final check = await deps.api.checkReference(frame.jpeg, itemLabel: _label);
        photo = _Photo(frame.jpeg, check.message, check.accepted);
      } on ApiException catch (e) {
        photo = _Photo(frame.jpeg, 'Photo kept but not checked: ${e.userMessage}', null);
      }
      setState(() => _photos.add(photo));
      _say(photo.accepted == true
          ? 'Photo ${_photos.length} saved. ${photo.note}'
          : 'Photo ${_photos.length} kept. ${photo.note} You can delete it and take another.');
    } on StateError {
      _say('The camera is not ready.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String text) {
    setState(() => _status = text);
    AppScope.of(context).guidance.announce(text, remember: false);
  }

  Future<void> _save() async {
    final deps = AppScope.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      _say('Please enter a name for the item first.');
      return;
    }
    if (_photos.isEmpty) {
      _say('Take at least one reference photo first.');
      return;
    }
    await deps.items.add(name: name, label: _label, photos: [for (final p in _photos) p.bytes]);
    await deps.guidance.announce('$name registered with ${_photos.length} photos.', remember: false);
    if (mounted) context.go('/items');
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Register an item',
      children: [
        TextField(
          key: const Key('item-name-field'),
          controller: _name,
          style: const TextStyle(fontSize: 18),
          decoration: const InputDecoration(labelText: 'Item name', hintText: 'For example: my blue phone'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _label,
          decoration: const InputDecoration(labelText: 'Item type'),
          items: [
            for (final e in kRegistrableItemTypes.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 18))),
          ],
          onChanged: _photos.isEmpty ? (v) => setState(() => _label = v ?? _label) : null,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Only these types can be detected by the current model. Take photos from different angles, '
            'with the item filling most of the view.',
            style: TextStyle(fontSize: 16),
          ),
        ),
        const CameraPanel(maxHeightFraction: 0.35),
        const SizedBox(height: 8),
        LabelledButton(
          key: const Key('take-reference-button'),
          icon: Icons.camera,
          label: _busy ? 'Checking photo…' : 'Take reference photo (${_photos.length}/$kMaxReferencePhotos)',
          onPressed: _busy ? null : _takePhoto,
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(liveRegion: true, child: Text(_status!, style: const TextStyle(fontSize: 18))),
          ),
        const SectionHeading('Reference photos'),
        for (final (i, p) in _photos.indexed)
          Card(
            child: ListTile(
              leading: Semantics(
                label: 'Reference photo ${i + 1}',
                image: true,
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Image.memory(p.bytes, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 40)),
                ),
              ),
              title: Text(
                'Photo ${i + 1}: ${p.accepted == true ? 'good' : p.accepted == false ? 'has issues' : 'not checked'}',
                style: const TextStyle(fontSize: 18),
              ),
              subtitle: Text(p.note, style: const TextStyle(fontSize: 16)),
              trailing: TextButton(
                onPressed: () => setState(() => _photos.removeAt(i)),
                child: const Text('Delete'),
              ),
            ),
          ),
        const SizedBox(height: 12),
        LabelledButton(key: const Key('save-item-button'), icon: Icons.save, label: 'Save item', onPressed: _save),
      ],
    );
  }
}
