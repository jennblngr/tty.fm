import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';

/// One entry of the bell's list. Kinds the app does not know are dropped
/// when parsing the list.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.read = false,
    this.data = const {},
  });

  final int id;
  final String kind; // "added"
  final DateTime createdAt;
  final bool read;
  final Map<String, dynamic> data;

  static const kinds = {'added'};

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: j['id'] as int,
    kind: j['kind'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch((j['created_at'] as int) * 1000),
    read: j['read'] as bool? ?? false,
    data: (j['data'] as Map<String, dynamic>?) ?? const {},
  );

  AppNotification copyWith({bool? read}) =>
      AppNotification(id: id, kind: kind, createdAt: createdAt, read: read ?? this.read, data: data);

  // "added": a batch of tracks came into the library.
  int get tracks => data['tracks'] as int? ?? 0;
  int get albums => data['albums'] as int? ?? 0;
  int? get albumId => data['album_id'] as int?;
  List<String> get artists => [for (final a in data['artists'] as List? ?? const []) a as String];
  int get artistCount => data['artist_count'] as int? ?? artists.length;
}

class NotificationList {
  const NotificationList(this.items);
  final List<AppNotification> items;

  int get unread => items.where((n) => !n.read).length;

  factory NotificationList.fromJson(Map<String, dynamic> j) => NotificationList([
    for (final n in j['items'] as List? ?? const [])
      if (AppNotification.kinds.contains((n as Map<String, dynamic>)['kind'])) AppNotification.fromJson(n),
  ]);
}

/// The server's notification routes. Servers without them (404) have no
/// notifications.
class NotificationsRepository {
  NotificationsRepository(this._api);
  final ApiClient _api;

  Future<NotificationList> list() async {
    try {
      return NotificationList.fromJson(await _api.get('/notifications') as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const NotificationList([]);
      rethrow;
    }
  }

  Future<void> setRead(int id, bool read) => _api.patch('/notifications/$id', {'read': read});

  Future<void> readAll() => _api.post('/notifications/read');

  /// Kind → on, for the kinds the server generates.
  Future<Map<String, bool>> settings() async =>
      (await _api.get('/notifications/settings') as Map<String, dynamic>).cast<String, bool>();

  Future<Map<String, bool>> setEnabled(String kind, bool on) async =>
      (await _api.patch('/notifications/settings', {kind: on}) as Map<String, dynamic>).cast<String, bool>();
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiProvider)),
);
