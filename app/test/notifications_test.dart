import 'package:flutter_test/flutter_test.dart';
import 'package:ttyfm/data/notifications.dart';
import 'package:ttyfm/ui/screens/notifications.dart';

void main() {
  final now = DateTime(2026, 11, 3, 22);
  int at(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  test('list: unknown kinds dropped, unread counted', () {
    final l = NotificationList.fromJson({
      'items': [
        {
          'id': 2,
          'kind': 'added',
          'created_at': at(DateTime(2026, 11, 2, 21, 14)),
          'read': false,
          'data': {
            'tracks': 3,
            'albums': 2,
            'artists': ['Faune', 'Racines'],
            'artist_count': 2,
          },
        },
        {'id': 3, 'kind': 'radar', 'created_at': at(now), 'read': false, 'data': {}},
        {
          'id': 1,
          'kind': 'added',
          'created_at': at(DateTime(2026, 10, 24, 9)),
          'read': true,
          'data': {
            'tracks': 1,
            'albums': 1,
            'album_id': 7,
            'artists': ['Kassette'],
          },
        },
      ],
      'unread': 2,
    });
    expect(l.items.map((n) => n.id), [2, 1]);
    expect(l.unread, 1);
    expect(l.items.last.albumId, 7);
    expect(l.items.last.artistCount, 1);
    expect(NotificationList.fromJson({}).items, isEmpty);
  });

  test('wording of "added"', () {
    final n = AppNotification(
      id: 1,
      kind: 'added',
      createdAt: DateTime(2026, 11, 2, 21, 14),
      data: const {
        'tracks': 3,
        'albums': 2,
        'artists': ['Faune', 'Racines'],
        'artist_count': 4,
      },
    );
    expect(notificationTitle(n), ('+ 3 titres ajoutés', 'faune, racines +2'));
    expect(notificationDetail(n, now), '// 2 albums · 21h14');
    final one = AppNotification(id: 2, kind: 'added', createdAt: now, data: const {'tracks': 1, 'albums': 1});
    expect(notificationTitle(one), ('+ 1 titre ajouté', null));
    expect(notificationDetail(one, now), '// 1 album · 22h00');
  });

  test('sections and dates', () {
    expect(notificationSection(DateTime(2026, 11, 3, 1), now), "aujourd'hui");
    expect(notificationSection(DateTime(2026, 11, 2, 23), now), 'hier');
    expect(notificationSection(DateTime(2026, 10, 28), now), 'cette semaine');
    expect(notificationSection(DateTime(2026, 10, 27), now), 'plus ancien');
    expect(notificationWhen(DateTime(2026, 11, 3, 8), now), '8h00');
    expect(notificationWhen(DateTime(2026, 11, 2, 21, 14), now), '21h14');
    expect(notificationWhen(DateTime(2026, 10, 28), now), 'mer.');
    expect(notificationWhen(DateTime(2026, 10, 24), now), '24 oct.');
  });
}
