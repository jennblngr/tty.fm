import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ttyfm/data/models.dart';
import 'package:ttyfm/state/library.dart';
import 'package:ttyfm/ui/screens/library.dart';
import 'package:ttyfm/ui/theme.dart';

final _follows = [
  FollowedArtist.fromJson({
    'id': 4,
    'name': 'Charlotte Cardin',
    'auto': true,
    'new_release': {'artist_id': 4, 'title': 'Memories', 'kind': 'single', 'released': '2026-10-09'},
  }),
  for (final (i, n) in ['Sia', 'Adele', 'Tove Lo', 'Kassette'].indexed) FollowedArtist(id: i + 10, name: n),
];

void main() {
  test('followed artists parse, with their new release', () {
    expect(_follows.first.newRelease!.title, 'Memories');
    expect(_follows.first.auto, isTrue);
    expect(FollowedArtist.fromJson({'id': 1}).newRelease, isNull);
  });

  testWidgets('artistes suivis: folded to four chips and +N, the dot, unfolded on tap', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [followsProvider.overrideWith((ref) => Stream.value(_follows))],
        child: MaterialApp(
          theme: ttyTheme(Tty.mocha),
          home: const Scaffold(body: FollowedArtists()),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('[5] ▾'), findsOneWidget);
    expect(find.textContaining('charlotte cardin •', findRichText: true), findsOneWidget);
    expect(find.textContaining('tove lo', findRichText: true), findsOneWidget);
    expect(find.textContaining('kassette', findRichText: true), findsNothing);
    expect(find.textContaining('+1', findRichText: true), findsOneWidget);
    expect(find.textContaining('• = nouvelle sortie', findRichText: true), findsOneWidget);

    await tester.tap(find.textContaining('+1', findRichText: true));
    await tester.pump();
    expect(find.textContaining('kassette', findRichText: true), findsOneWidget);
    expect(find.text('[5] ▴'), findsOneWidget);
  });
}
