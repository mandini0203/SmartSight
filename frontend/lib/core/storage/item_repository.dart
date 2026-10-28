import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_exception.dart';
import '../auth/profile.dart';

/// A registered personal item. Its reference photos are kept on the phone,
/// and for a signed-in user also on the server so they follow the account.
class PersonalItem {
  const PersonalItem({
    required this.id,
    required this.name,
    required this.label,
    required this.referencePaths,
    required this.createdAt,
    this.synced = false,
  });

  factory PersonalItem.fromJson(Map<String, dynamic> j) => PersonalItem(
        id: j['id'] as String,
        name: j['name'] as String,
        label: j['label'] as String,
        referencePaths: (j['referencePaths'] as List).cast<String>(),
        createdAt: DateTime.parse(j['createdAt'] as String),
        synced: j['synced'] as bool? ?? false,
      );

  final String id;
  final String name;

  /// Detector (COCO) class used to locate candidates, e.g. "cell phone".
  final String label;
  final List<String> referencePaths;
  final DateTime createdAt;

  /// Saved to the signed-in user's account on the server.
  final bool synced;

  PersonalItem copyWith({bool? synced, List<String>? referencePaths}) => PersonalItem(
      id: id,
      name: name,
      label: label,
      referencePaths: referencePaths ?? this.referencePaths,
      createdAt: createdAt,
      synced: synced ?? this.synced);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'label': label,
        'referencePaths': referencePaths,
        'createdAt': createdAt.toIso8601String(),
        'synced': synced,
      };
}

/// Detector classes offered when registering an item: portable objects a
/// person is likely to misplace that pretrained COCO YOLOv8 can detect.
const Map<String, String> kRegistrableItemTypes = {
  'cell phone': 'Phone',
  'handbag': 'Handbag or purse',
  'backpack': 'Backpack',
  'suitcase': 'Suitcase',
  'umbrella': 'Umbrella',
  'bottle': 'Bottle',
  'cup': 'Cup or mug',
  'laptop': 'Laptop',
  'book': 'Book',
  'remote': 'Remote control',
  'keyboard': 'Keyboard',
  'mouse': 'Computer mouse',
  'scissors': 'Scissors',
  'teddy bear': 'Soft toy',
  'toothbrush': 'Toothbrush',
};

/// The signed-in user's items on the server.
abstract class ItemRemote {
  Future<List<RemoteItem>> list();
  Future<void> upload(PersonalItem item, List<Uint8List> photos);
  Future<void> delete(String id);
  Future<Uint8List> photo(String id, int index);
}

abstract class ItemRepository extends ChangeNotifier {
  Future<void> load();
  List<PersonalItem> get items;
  Future<PersonalItem> add({required String name, required String label, required List<Uint8List> photos});
  Future<void> delete(String id);
  Future<List<Uint8List>> references(PersonalItem item);

  /// Signed-in account whose items are shown; null for the guest list.
  String? get ownerId => null;

  /// Shows the item list of [ownerId] (null = guest) and syncs it through
  /// [remote] when given.
  Future<void> switchAccount(String? ownerId, {ItemRemote? remote}) async {}

  /// Uploads items saved while offline and downloads items added on other
  /// phones. Does nothing for guests.
  Future<void> sync() async {}

  /// Removes this phone's copy of a deleted account's items.
  Future<void> deleteAccountData(String ownerId) async {}

  PersonalItem? byId(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  PersonalItem? firstWithLabel(String label) {
    for (final i in items) {
      if (i.label == label) return i;
    }
    return null;
  }
}

class FileItemRepository extends ItemRepository {
  List<PersonalItem> _items = [];
  Directory? _dir;
  String? _owner;
  ItemRemote? _remote;
  Future<void>? _syncing;

  @override
  List<PersonalItem> get items => List.unmodifiable(_items);

  @override
  String? get ownerId => _owner;

  Future<Directory> _root() async {
    final docs = (await getApplicationDocumentsDirectory()).path;
    // Guest items stay where earlier versions of the app kept them.
    final d = _dir ?? Directory(_owner == null ? '$docs/personal_items' : '$docs/accounts/$_owner/personal_items');
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  Future<File> _index() async => File('${(await _root()).path}/items.json');

  @override
  Future<void> deleteAccountData(String ownerId) async {
    final d = Directory('${(await getApplicationDocumentsDirectory()).path}/accounts/$ownerId');
    if (await d.exists()) await d.delete(recursive: true);
  }

  @override
  Future<void> load() async {
    try {
      final f = await _index();
      _items = await f.exists()
          ? [for (final e in jsonDecode(await f.readAsString()) as List) PersonalItem.fromJson(e as Map<String, dynamic>)]
          : [];
    } catch (_) {
      _items = [];
    }
    notifyListeners();
  }

  @override
  Future<void> switchAccount(String? ownerId, {ItemRemote? remote}) async {
    if (ownerId == _owner && remote == _remote) return;
    _owner = ownerId;
    _remote = ownerId == null ? null : remote;
    _dir = null;
    await load();
    await sync();
  }

  Future<void> _save() async {
    await (await _index()).writeAsString(jsonEncode(_items.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Future<List<String>> _writePhotos(String id, List<Uint8List> photos) async {
    final root = await _root();
    final paths = <String>[];
    for (var i = 0; i < photos.length; i++) {
      final f = File('${root.path}/${id}_$i.jpg');
      await f.writeAsBytes(photos[i], flush: true);
      paths.add(f.path);
    }
    return paths;
  }

  @override
  Future<PersonalItem> add({required String name, required String label, required List<Uint8List> photos}) async {
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    var item = PersonalItem(
        id: id, name: name, label: label, referencePaths: await _writePhotos(id, photos), createdAt: DateTime.now());
    _items = [..._items, item];
    await _save();
    final remote = _remote;
    if (remote != null) {
      try {
        await remote.upload(item, photos);
        item = item.copyWith(synced: true);
        _replace(item);
        await _save();
      } on ApiException {
        // Kept on the phone; uploaded by the next sync.
      }
    }
    return item;
  }

  void _replace(PersonalItem item) => _items = [for (final i in _items) i.id == item.id ? item : i];

  /// Throws [ApiException] when a synced item cannot be removed from the
  /// server, so it does not come back at the next sync.
  @override
  Future<void> delete(String id) async {
    final item = byId(id);
    if (item == null) return;
    final remote = _remote;
    if (remote != null && item.synced) {
      try {
        await remote.delete(id);
      } on ApiException catch (e) {
        if (e.kind != ApiErrorKind.notFound) rethrow;
      }
    }
    await _deleteLocal(item);
    await _save();
  }

  Future<void> _deleteLocal(PersonalItem item) async {
    for (final p in item.referencePaths) {
      final f = File(p);
      if (await f.exists()) await f.delete();
    }
    _items = _items.where((i) => i.id != item.id).toList();
  }

  @override
  Future<List<Uint8List>> references(PersonalItem item) async {
    final out = <Uint8List>[];
    for (final p in item.referencePaths) {
      final f = File(p);
      if (await f.exists()) out.add(await f.readAsBytes());
    }
    return out;
  }

  @override
  Future<void> sync() => _syncing ??= _sync().whenComplete(() => _syncing = null);

  Future<void> _sync() async {
    final remote = _remote;
    final owner = _owner;
    if (remote == null) return;
    try {
      final server = await remote.list();
      if (owner != _owner) return; // account changed while waiting
      final serverIds = {for (final r in server) r.id};
      final localIds = {for (final i in _items) i.id};

      for (final local in [..._items]) {
        if (!local.synced) {
          await remote.upload(local, await references(local));
          _replace(local.copyWith(synced: true));
        } else if (!serverIds.contains(local.id)) {
          await _deleteLocal(local); // deleted on another phone
        }
      }
      for (final r in server.where((r) => !localIds.contains(r.id))) {
        final photos = [for (var i = 0; i < r.photoCount; i++) await remote.photo(r.id, i)];
        if (owner != _owner) return;
        _items = [
          ..._items,
          PersonalItem(id: r.id, name: r.name, label: r.label, referencePaths: await _writePhotos(r.id, photos),
              createdAt: r.createdAt.toLocal(), synced: true),
        ];
      }
      _items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await _save();
    } on ApiException {
      // Offline or signed out: the local list stays usable; retried later.
    }
  }
}
