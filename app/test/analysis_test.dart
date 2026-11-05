import 'package:flutter_test/flutter_test.dart';
import 'package:ttyfm/data/models.dart';

void main() {
  test('analysis from the API', () {
    final r = AnalysisResult.fromJson({
      'analysis': {
        'track_id': 1,
        'bpm': 118,
        'key': 'A',
        'scale': 'minor',
        'camelot': '8A',
        'energy': 0.72,
        'loudness_lufs': -8.2,
        'genres': [
          {'name': 'électro', 'share': 0.68},
          {'name': 'synthwave', 'share': 0.24},
        ],
        'stale': false,
      },
      'compatible': [
        {
          'id': 2,
          'title': 'marée basse',
          'artist_id': 1,
          'artist': 'les échos',
          'album_id': 1,
          'album': 'x',
          'duration_ms': 1000,
          'bpm': 120.0,
          'camelot': '8A',
        },
      ],
    });
    final a = r.analysis;
    expect(a.bpm, 118.0);
    expect(a.keyName, 'la mineur');
    expect(a.genres.first, ('électro', 0.68));
    expect(a.danceability, isNull);
    expect(r.compatible.single.bpm, 120.0);
    expect(r.compatible.single.camelot, '8A');
  });

  test('french key names', () {
    expect(const TrackAnalysis(key: 'A#', scale: 'major').keyName, 'si♭ majeur');
    expect(const TrackAnalysis(key: 'F#', scale: 'minor').keyName, 'fa♯ mineur');
    expect(const TrackAnalysis().keyName, isNull);
  });

  test('track bpm survives the cache', () {
    const t = Track(id: 1, title: 't', artistId: 1, artist: 'a', albumId: 1, album: 'b', durationMs: 1, bpm: 124);
    final back = Track.fromJson(t.toJson());
    expect(back.bpm, 124.0);
    expect(back.camelot, isNull);
    expect(t.toJson().containsKey('camelot'), isFalse);
  });
}
