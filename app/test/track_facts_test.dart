import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ttyfm/data/models.dart';
import 'package:ttyfm/state/search.dart';
import 'package:ttyfm/ui/shell.dart';
import 'package:ttyfm/ui/theme.dart';

const _track = Track(
  id: 1,
  title: 'néons',
  artistId: 1,
  artist: 'nova kid',
  albumId: 1,
  album: 'x',
  durationMs: 1000,
  genre: 'Electronic',
  format: 'flac',
);

Future<void> _pump(WidgetTester tester, AnalysisResult? result) => tester.pumpWidget(
  ProviderScope(
    overrides: [analysisProvider(1).overrideWith((ref) async => result)],
    child: MaterialApp(
      theme: ttyTheme(Tty.mocha),
      home: const Scaffold(body: TrackFacts(_track)),
    ),
  ),
);

void main() {
  testWidgets('without analysis: tags and file only', (tester) async {
    await _pump(tester, null);
    await tester.pump();
    expect(find.text('electronic'), findsOneWidget);
    expect(find.text('tempo'), findsNothing);
  });

  testWidgets('with analysis: tempo, key, meters, loudness', (tester) async {
    await _pump(
      tester,
      const AnalysisResult(
        TrackAnalysis(
          bpm: 118,
          key: 'A',
          scale: 'minor',
          camelot: '8A',
          energy: 0.72,
          danceability: 0.61,
          loudnessLufs: -8.2,
        ),
        [],
      ),
    );
    await tester.pump();
    expect(find.text('tempo'), findsOneWidget);
    expect(find.textContaining('118 bpm', findRichText: true), findsOneWidget);
    expect(find.textContaining('la mineur', findRichText: true), findsOneWidget);
    expect(find.textContaining('(8A)', findRichText: true), findsOneWidget);
    expect(find.textContaining('72%', findRichText: true), findsOneWidget);
    expect(find.text('-8.2 LUFS'), findsOneWidget);
    expect(find.text('acoustique'), findsNothing);
  });

  testWidgets('a failed analysis shows nothing of it', (tester) async {
    await _pump(tester, const AnalysisResult(TrackAnalysis(error: 'decode', bpm: 100), []));
    await tester.pump();
    expect(find.text('tempo'), findsNothing);
  });
}
