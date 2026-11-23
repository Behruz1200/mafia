import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';

/// The room the player last had open, kept across launches, so the home
/// screen can take them back into a match they are still in after a reload,
/// an app restart or a second browser tab. Without it they sit on the home
/// screen, go offline, and the server forfeits their stake after 60 s.
abstract interface class LastRoomStore {
  Future<RoomId?> read();
  Future<void> write(RoomId? roomId);
}

class SecureLastRoomStore implements LastRoomStore {
  const SecureLastRoomStore([this._storage = const FlutterSecureStorage()]);

  static const _key = 'mafia.lastRoom';
  final FlutterSecureStorage _storage;

  @override
  Future<RoomId?> read() async {
    try {
      return await _storage.read(key: _key);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(RoomId? roomId) async {
    try {
      roomId == null
          ? await _storage.delete(key: _key)
          : await _storage.write(key: _key, value: roomId);
    } on Object {
      // Only a convenience: the game works without it.
    }
  }
}

/// For fakes and tests.
class MemoryLastRoomStore implements LastRoomStore {
  MemoryLastRoomStore([this.roomId]);
  RoomId? roomId;

  @override
  Future<RoomId?> read() async => roomId;

  @override
  Future<void> write(RoomId? roomId) async => this.roomId = roomId;
}

final lastRoomStoreProvider = Provider<LastRoomStore>(
  (ref) =>
      AppConfig.useFakes ? MemoryLastRoomStore() : const SecureLastRoomStore(),
);
