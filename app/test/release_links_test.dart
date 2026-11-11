import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ttyfm/data/models.dart';
import 'package:ttyfm/state/library.dart';
import 'package:ttyfm/ui/links.dart';
import 'package:ttyfm/ui/screens/releases.dart';
import 'package:ttyfm/ui/theme.dart';

final _releases = [
  NewRelease.fromJson({
    'artist_id': 1,
    'artist': 'Sia',
    'mbid': 'rg-1',
    'title': 'Reasonable Woman',
    'kind': 'album',
    'released': '2026-10-02',
  }),
  NewRelease.fromJson({
    'artist_id': 2,
    'artist': 'Adele',
    'mbid': 'rg-2',
    'title': '30',
    'kind': 'album',
    'released': '2026-09-01',
    'album_id': 7,
  }),
  // Older servers sent no mbid: nothing to open.
  NewRelease.fromJson({'artist_id': 3, 'artist': 'Lorde', 'title': 'Virgin', 'kind': 'album', 'released': '2026-08'}),
];

void main() {
  test('links: MusicBrainz release group, ListenBrainz artist', () {
    expect(musicBrainzReleaseGroup('rg-1').toString(), 'https://musicbrainz.org/release-group/rg-1');
    expect(listenBrainzArtist('a-1').toString(), 'https://listenbrainz.org/artist/a-1/');
    expect(_releases[0].mbid, 'rg-1');
    expect(_releases[2].mbid, '');
  });

  testWidgets('releases in full: count, [+] when missing, [✓] when in the library', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [releasesProvider.overrideWith((ref) => Stream.value(_releases))],
        child: MaterialApp(theme: ttyTheme(Tty.mocha), home: const ReleasesScreen()),
      ),
    );
    await tester.pump();
    expect(find.textContaining('3 sorties · 90 derniers jours et à venir', findRichText: true), findsOneWidget);
    expect(find.text('reasonable woman'), findsOneWidget);
    expect(find.text('[+]'), findsOneWidget);
    expect(find.text('[✓]'), findsOneWidget);
  });
}
