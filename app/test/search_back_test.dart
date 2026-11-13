import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ttyfm/data/library_repository.dart';
import 'package:ttyfm/data/models.dart';
import 'package:ttyfm/playback/audio_engine.dart';
import 'package:ttyfm/playback/playback_controller.dart';
import 'package:ttyfm/state/playback.dart';
import 'package:ttyfm/state/search.dart';
import 'package:ttyfm/ui/screens/search.dart';
import 'package:ttyfm/ui/shell.dart';
import 'package:ttyfm/ui/theme.dart';

/// Answers every search with nothing, and records the filters.
class _Repo implements LibraryRepository {
  final searches = <SearchFilter>[];

  @override
  Future<SearchResult> search(
    String q, {
    SearchFilter filter = const SearchFilter(),
    int limit = 20,
    CancelToken? cancel,
  }) async {
    searches.add(filter);
    return const SearchResult();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An engine that never plays: the search screen only needs a controller.
/// (The stream types come from [AudioEngine].)
class _Engine implements AudioEngine {
  @override
  get index => const Stream.empty();
  @override
  get playing => const Stream.empty();
  @override
  get buffering => const Stream.empty();
  @override
  get position => const Stream.empty();
  @override
  get duration => const Stream.empty();
  @override
  get completed => const Stream.empty();
  @override
  get errors => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('back clears the query and the filters first, then goes to the shell (#2)', (tester) async {
    bool Function()? back;
    final repo = _Repo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryProvider.overrideWithValue(repo),
          searchFacetsProvider.overrideWith((ref) => Stream.value(const SearchFacets(genres: [Facet('Pop', 3)]))),
          playbackControllerProvider.overrideWithValue(
            PlaybackController(_Engine(), sourceFor: (t) => EngineSource('u${t.id}')),
          ),
        ],
        child: MaterialApp(
          theme: ttyTheme(Tty.mocha),
          home: ShellScope(
            open: (_, _) {},
            select: (_) {},
            setBackHandler: (tab, handler) {
              expect(tab, searchTab);
              back = handler;
            },
            child: const Scaffold(body: SearchScreen()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(back, isNotNull);
    // Nothing to clear: the shell handles it.
    expect(back!(), isFalse);

    // A genre tile of "parcourir" sets a filter; back clears it.
    await tester.tap(find.text('pop'));
    await tester.pumpAndSettle();
    expect(repo.searches.last.isActive, isTrue);
    expect(find.text('pop'), findsNothing); // results, not "parcourir"
    expect(back!(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('pop'), findsOneWidget); // back to "parcourir"
    expect(back!(), isFalse);

    // A query too.
    await tester.enterText(find.byType(TextField), 'sia');
    await tester.pumpAndSettle();
    expect(back!(), isTrue);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    expect(back!(), isFalse);
  });
}
