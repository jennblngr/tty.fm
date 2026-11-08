import 'package:flutter_test/flutter_test.dart';
import 'package:ttyfm/data/models.dart';
import 'package:ttyfm/ui/screens/home.dart';

void main() {
  test('recently played: albums, artists and playlists, unknown kinds skipped', () {
    final h = HomeData.fromJson({
      'recently_added': [],
      'recently_played': [
        {
          'kind': 'album',
          'album': {'id': 1, 'title': 'halo', 'artist_id': 2, 'artist': 'mira sol', 'track_count': 3, 'duration_ms': 0},
        },
        {
          'kind': 'artist',
          'artist': {'id': 2, 'name': 'nova kid', 'album_count': 1},
        },
        {
          'kind': 'playlist',
          'playlist': {
            'id': 3,
            'name': 'lo-fi pour coder',
            'cover_ids': [1, 2, 3, 4],
          },
        },
        {'kind': 'radio'},
      ],
    });
    expect(h.recentlyPlayed.map((r) => r.album?.title ?? r.artist?.name ?? r.playlist?.name), [
      'halo',
      'nova kid',
      'lo-fi pour coder',
    ]);
    expect(h.recentlyPlayed[2].playlist!.coverIds, [1, 2, 3, 4]);
  });

  test('recently played: older servers send albums only', () {
    final h = HomeData.fromJson({
      'recently_added': [],
      'recently_played_albums': [
        {'id': 1, 'title': 'halo', 'artist_id': 2, 'artist': 'mira sol', 'track_count': 3, 'duration_ms': 0},
      ],
    });
    expect(h.recentlyPlayed.single.album?.title, 'halo');
  });

  test('recently added: batches, or whole albums from older servers', () {
    const racines = {
      'id': 1,
      'title': 'racines',
      'artist_id': 2,
      'artist': 'faune',
      'track_count': 5,
      'duration_ms': 0,
    };
    final h = HomeData.fromJson({
      'recent_additions': [
        {'album': racines, 'tracks': 3, 'added_at': 1700000000},
      ],
      'recently_played': [],
    });
    final r = h.recentlyAdded.single;
    expect((r.tracks, r.wholeAlbum, r.addedAt), (3, false, DateTime.fromMillisecondsSinceEpoch(1700000000000)));

    final old = HomeData.fromJson({
      'recently_added': [
        {...racines, 'created_at': 1700000000},
      ],
      'recently_played': [],
    });
    expect((old.recentlyAdded.single.tracks, old.recentlyAdded.single.wholeAlbum), (5, true));
  });

  test('mixes of the day: parsed, with their caption; none from older servers', () {
    final h = HomeData.fromJson({
      'recent_additions': [],
      'recently_played': [],
      'mixes': [
        {
          'position': 1,
          'name': 'mix_01',
          'description': 'dance-pop · calme',
          'artists': ['Sia', 'Tove Lo'],
          'cover_ids': [3, 4],
          'track_count': 25,
          'duration_ms': 5460000,
        },
        {'position': 2, 'artists': []},
      ],
    });
    expect(h.mixes.map((m) => m.name), ['mix_01', 'mix_02']);
    expect(h.mixes[0].caption, 'dance-pop · calme · sia, tove lo…');
    expect(h.mixes[0].coverIds, [3, 4]);
    expect(h.mixes[1].caption, '');
    expect(HomeData.fromJson({'recent_additions': [], 'recently_played': []}).mixes, isEmpty);
  });

  test('new releases: parsed, month-only dates, subtitles', () {
    final h = HomeData.fromJson({
      'recent_additions': [],
      'recently_played': [],
      'new_releases': [
        {
          'artist_id': 4,
          'artist': 'Charlotte Cardin',
          'title': 'Midnight, mon amour',
          'kind': 'album',
          'released': '2027-01-29',
          'upcoming': true,
        },
        {'artist_id': 1, 'artist': 'Sia', 'title': 'DISGUISE', 'kind': 'single', 'released': '2026-08', 'album_id': 9},
        {'artist_id': 1, 'artist': 'Sia', 'title': 'X', 'kind': 'ep', 'released': '2026'},
      ],
    });
    final now = DateTime(2026, 11, 9);
    final r = h.newReleases;
    expect(r[1].albumId, 9);
    expect(r[1].date, DateTime(2026, 8, 1));
    expect(newReleaseSubtitle(r[0], now: now), 'charlotte cardin · album · à venir le 29 janv. 2027');
    expect(newReleaseSubtitle(r[1], now: now), 'sia · single · sorti en août');
    expect(newReleaseSubtitle(r[2], now: now), 'sia · EP');
    expect(HomeData.fromJson({'recent_additions': [], 'recently_played': []}).newReleases, isEmpty);
  });
}
