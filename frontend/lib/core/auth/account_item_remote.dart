import 'dart:typed_data';

import '../storage/item_repository.dart';
import 'auth_controller.dart';
import 'profile.dart';

/// The signed-in user's items at /api/v1/me/items.
class AccountItemRemote implements ItemRemote {
  AccountItemRemote(this.auth);

  final AuthController auth;

  @override
  Future<List<RemoteItem>> list() => auth.authed((api, token) => api.myItems(token));

  @override
  Future<void> upload(PersonalItem item, List<Uint8List> photos) => auth.authed((api, token) =>
      api.uploadMyItem(token, id: item.id, name: item.name, label: item.label, photos: photos));

  @override
  Future<void> delete(String id) => auth.authed((api, token) => api.deleteMyItem(token, id));

  @override
  Future<Uint8List> photo(String id, int index) => auth.authed((api, token) => api.myItemPhoto(token, id, index));
}
