import 'package:flutter_test/flutter_test.dart';
import 'package:ttyfm/data/models.dart';

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
}
