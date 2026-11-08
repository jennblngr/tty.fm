import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ttyfm/core/settings.dart';
import 'package:ttyfm/data/models.dart';
import 'package:ttyfm/state/search.dart';
import 'package:ttyfm/ui/screens/settings.dart';
import 'package:ttyfm/ui/screens/stats.dart';
import 'package:ttyfm/ui/theme.dart';

Map<String, dynamic> _track(int id, String title, double bpm) => {
  'id': id,
  'title': title,
  'artist_id': 1,
  'artist': 'nova kid',
  'album_id': 1,
  'album': 'x',
  'duration_ms': 1000,
  'bpm': bpm,
};

final _stats = {
  'days': 30,
  'total_ms': 600000,
  'plays': 5,
  'distinct_tracks': 3,
  'tempo': {
    'analyzed_ms': 400000,
    'band_ms': [40000, 0, 200000, 0, 160000],
    'avg_bpm': 118,
    'prev_avg_bpm': 114,
    'morning_bpm': 124,
    'evening_bpm': 98,
    'fastest': _track(2, 'Sprint', 172),
    'slowest': _track(3, 'Pluie fine', 78),
  },
};

void main() {
  test('tempo and analysis status parse, old servers included', () {
    final t = ListeningStats.fromJson(_stats).tempo;
    expect(t.bandMs, [40000, 0, 200000, 0, 160000]);
    expect((t.avgBpm, t.prevAvgBpm, t.fastest!.title, t.slowest!.bpm), (118.0, 114.0, 'Sprint', 78.0));
    expect(ListeningStats.fromJson({'plays': 0}).tempo.analyzedMs, 0);

    final st = AnalysisStatus.fromJson({'enabled': false, 'total': 345, 'analyzed': 340, 'failed': 2, 'pending': 3});
    expect(analysisSummary(st), '340 / 345 titres analysés · 3 en pause · 2 en échec');
    expect(analysisSummary(AnalysisStatus.fromJson({'total': 4, 'analyzed': 4})), '4 / 4 titres analysés');
    expect(AnalysisStatus.fromJson({}).enabled, isTrue); // older servers: no switch
  });

  testWidgets('the tempo panel', (tester) async {
    tester.view.physicalSize = const Size(500, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          statsProvider.overrideWith((ref, days) => Stream.value(ListeningStats.fromJson(_stats))),
        ],
        child: MaterialApp(
          theme: ttyTheme(Tty.mocha),
          home: const Scaffold(body: StatsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('tempo [', findRichText: true), findsOneWidget);
    expect(find.text('100–120'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget); // 200 000 of 400 000 ms
    expect(find.textContaining('118 ↑4', findRichText: true), findsOneWidget);
    expect(find.textContaining('sprint — 172 bpm', findRichText: true), findsOneWidget);
    expect(find.textContaining('pluie fine — 78 bpm', findRichText: true), findsOneWidget);
    expect(find.textContaining('plus rapide le matin (124) que le soir (98)', findRichText: true), findsOneWidget);
  });
}
