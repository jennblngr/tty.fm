import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/session.dart';
import '../data/notifications.dart';

/// The bell's list. The server generates notifications when they are
/// read, so fetching it also catches up with the library. Marking as read
/// is optimistic.
class NotificationsNotifier extends AsyncNotifier<NotificationList> {
  @override
  Future<NotificationList> build() {
    ref.watch(tokenProvider);
    return ref.watch(notificationsRepositoryProvider).list();
  }

  NotificationsRepository get _repo => ref.read(notificationsRepositoryProvider);

  Future<void> _optimistic(NotificationList next, Future<void> Function() send) async {
    final cur = state.value;
    state = AsyncData(next);
    try {
      await send();
    } catch (_) {
      if (cur != null) state = AsyncData(cur); // revert
      rethrow;
    }
  }

  Future<void> setRead(int id, bool read) async {
    final cur = state.value;
    if (cur == null) return;
    await _optimistic(
      NotificationList([for (final n in cur.items) n.id == id ? n.copyWith(read: read) : n]),
      () => _repo.setRead(id, read),
    );
  }

  Future<void> readAll() async {
    final cur = state.value;
    if (cur == null || cur.unread == 0) return;
    await _optimistic(NotificationList([for (final n in cur.items) n.copyWith(read: true)]), _repo.readAll);
  }
}

final notificationsProvider = AsyncNotifierProvider<NotificationsNotifier, NotificationList>(NotificationsNotifier.new);

/// Unread count for the bell's dot: 0 while loading, offline or on error.
final unreadNotificationsProvider = Provider<int>((ref) => ref.watch(notificationsProvider).value?.unread ?? 0);

/// Kind → on, as the server has it.
final notificationSettingsProvider = FutureProvider.autoDispose<Map<String, bool>>((ref) {
  ref.watch(tokenProvider);
  return ref.watch(notificationsRepositoryProvider).settings();
});
