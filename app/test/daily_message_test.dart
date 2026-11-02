import 'package:flutter_test/flutter_test.dart';
import 'package:ttyfm/data/models.dart';
import 'package:ttyfm/ui/daily_message.dart';

RecentAddition _album(DateTime added) => RecentAddition(
  album: Album(id: 1, title: 'faune', artistId: 1, artist: 'x', trackCount: 3),
  tracks: 3,
  addedAt: added,
);

ListeningStats _stats({int totalMs = 0, int? prevTotalMs, List<(Track, int)> top = const []}) => ListeningStats(
  days: 30,
  totalMs: totalMs,
  prevTotalMs: prevTotalMs,
  plays: 0,
  distinctTracks: 0,
  weekdayAvgMin: List.filled(7, 0),
  hourMs: List.filled(24, 0),
  topArtists: const [],
  topGenres: const [],
  topTracks: top,
);

Track _track(String title) =>
    Track(id: 1, title: title, artistId: 1, artist: 'x', albumId: 7, album: 'y', durationMs: 1);

void main() {
  final noon = DateTime(2026, 11, 12, 12);
  final old = HomeData(recentlyAdded: [_album(DateTime(2026, 1, 1))]);

  test('empty library, then the greeting alone', () {
    expect(pickDailyMessage(now: noon, home: const HomeData()).text, '// bonjour. bibliothèque vide.');
    expect(pickDailyMessage(now: DateTime(2026, 11, 12, 20), home: old).text, '// bonsoir.');
  });

  test('albums added since the last opening come first', () {
    final home = HomeData(recentlyAdded: [_album(DateTime(2026, 11, 11)), _album(DateTime(2026, 11, 12, 9))]);
    final m = pickDailyMessage(
      now: noon,
      home: home,
      lastOpen: DateTime(2026, 11, 10),
      month: _stats(totalMs: 1 << 30),
    );
    expect(m.text, '// 2 ajouts récents.');
    expect(m.highlight, '2');
    expect(pickDailyMessage(now: noon, home: home, lastOpen: DateTime(2026, 11, 12, 8)).text, '// 1 ajout récent.');
  });

  test('hours this month with the trend, from the 7th', () {
    final s = _stats(totalMs: 51 * 3600000, prevTotalMs: 47 * 3600000);
    expect(pickDailyMessage(now: noon, home: old, month: s).text, '// 51h ce mois-ci. ↑9%.');
    expect(pickDailyMessage(now: DateTime(2026, 11, 3, 12), home: old, month: s).id, 'repli.salut');
  });

  test('a long track title is cut to fit 45 characters', () {
    final s = _stats(top: [(_track('une très longue chanson qui ne tient pas'), 37)]);
    final m = pickDailyMessage(now: noon, home: old, last30: s);
    expect(m.id, 'clin-oeil.repeat');
    expect(m.text.length, lessThanOrEqualTo(maxLength));
    expect(m.text, endsWith('… : 37 écoutes. on change ?'));
    expect(m.seed, 7);
  });

  test('never the same P3/P4 twice in a row', () {
    final s = _stats(totalMs: 10 * 3600000);
    final night = DateTime(2026, 11, 12, 2);
    for (var seed = 0; seed < 20; seed++) {
      final m = pickDailyMessage(now: night, home: old, month: s, previousId: 'stats.mois', seed: seed);
      expect(m.id, 'moment.nuit');
    }
    expect(pickDailyMessage(now: night, home: old, previousId: 'moment.nuit').id, 'moment.nuit');
  });

  test('every message holds on one line', () {
    final night = DateTime(2026, 11, 30, 4);
    final s = _stats(totalMs: 999 * 3600000, prevTotalMs: 1, top: [(_track('x' * 60), 999)]);
    for (var seed = 0; seed < 20; seed++) {
      final m = pickDailyMessage(now: night, home: old, month: s, last30: s, milestone: 100000, seed: seed);
      expect(m.text.length, lessThanOrEqualTo(maxLength), reason: m.text);
    }
  });

  test('milestones: recorded silently the first time, shown for a day', () {
    final now = DateTime(2026, 11, 12);
    final (show0, store0) = checkMilestone(5200, null, now);
    expect(show0, isNull);
    expect(store0!.$1, 5000);
    final (show1, store1) = checkMilestone(10100, store0, now);
    expect(show1, 10000);
    expect(checkMilestone(10200, store1, now.add(const Duration(hours: 5))).$1, 10000);
    expect(checkMilestone(10200, store1, now.add(const Duration(days: 2))).$1, isNull);
    expect(pickDailyMessage(now: noon, home: old, milestone: 5000).text, '// 5 000 titres dans ta biblio.');
  });
}
