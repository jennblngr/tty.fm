// End-to-end test of the real app against a running server.
//
//   cd server && SELFSTREAM_MUSIC_DIR=../data/dev-music SELFSTREAM_DATA_DIR=../data/dev-data \
//     SELFSTREAM_ADMIN_PASSWORD=devpass SELFSTREAM_LISTEN=127.0.0.1:4533 ./bin/selfstream
//   cd app && flutter test integration_test -d macos \
//     --dart-define=SERVER=127.0.0.1:4533 --dart-define=PASSWORD=devpass
//
// Screenshots are written to the app's support directory (path printed).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:selfstream/data/library_repository.dart';
import 'package:selfstream/main.dart' as app;
import 'package:selfstream/state/library.dart';
import 'package:selfstream/state/playback.dart';

const server = String.fromEnvironment('SERVER', defaultValue: '127.0.0.1:4533');
const password = String.fromEnvironment('PASSWORD', defaultValue: 'devpass');

/// Seconds to keep the app alive after the test (to pull screenshots from
/// a device before the test runner uninstalls the app).
const holdSeconds = int.fromEnvironment('HOLD');

Future<void> waitFor(WidgetTester tester, Finder f, {Duration timeout = const Duration(seconds: 15)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (f.evaluate().isNotEmpty) return;
  }
  final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().toList();
  await shot(tester, 'timeout');
  throw TestFailure('Timed out waiting for $f. Visible texts: $texts');
}

Future<void> settle(WidgetTester tester, [Duration d = const Duration(milliseconds: 800)]) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.pump();
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final image = await layer.toImage(view.paintBounds, pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/screenshots');
  await dir.create(recursive: true);
  final f = File('${dir.path}/$name.png');
  await f.writeAsBytes(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('SCREENSHOT ${f.path}');
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login, browse, play, playlists', (tester) async {
    await app.main();
    await settle(tester, const Duration(seconds: 2));

    // --- login (skipped if a token is already stored) -----------------------
    if (find.text('Se connecter').evaluate().isNotEmpty) {
      await tester.enterText(find.widgetWithText(TextField, 'Adresse du serveur'), server);
      await tester.enterText(find.widgetWithText(TextField, 'Mot de passe'), password);
      await shot(tester, '01_login');
      await tester.tap(find.text('Se connecter'));
    }
    await waitFor(tester, find.text('Ajouts récents'), timeout: const Duration(seconds: 40)); // cold start on emulators
    await settle(tester, const Duration(seconds: 2)); // covers
    await shot(tester, '02_home');

    // --- library: albums grid, then album page ------------------------------
    await tester.tap(find.text('Bibliothèque').first);
    await settle(tester);
    await tester.tap(find.text('Albums'));
    await settle(tester, const Duration(seconds: 2));
    await shot(tester, '03_albums');
    await tester.tap(find.text('Blue Hours').first);
    await waitFor(tester, find.text('Lire'));
    await settle(tester, const Duration(seconds: 1));
    await shot(tester, '04_album');

    // --- playback through media_kit ------------------------------------------
    final c = containerOf(tester).read(playbackControllerProvider);
    await tester.tap(find.text('Lire'));
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (c.position < const Duration(seconds: 2) && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(c.state.playing, isTrue, reason: 'player should be playing');
    expect(c.position, greaterThanOrEqualTo(const Duration(seconds: 2)), reason: 'position should advance');
    expect(c.state.current!.title, 'Track 1 of Blue Hours');
    await shot(tester, '05_playing_album');

    await c.next();
    await settle(tester, const Duration(seconds: 2));
    expect(c.state.current!.title, 'Track 2 of Blue Hours');
    expect(c.state.playing, isTrue);

    // Seek near the end and let the engine advance on its own (gapless path).
    await c.seek(const Duration(seconds: 38));
    final end2 = DateTime.now().add(const Duration(seconds: 10));
    while (c.state.index != 2 && DateTime.now().isBefore(end2)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(c.state.current!.title, 'Track 3 of Blue Hours', reason: 'natural advance');

    // Full player screen.
    await tester.tap(find.text('Track 3 of Blue Hours').last);
    await settle(tester, const Duration(seconds: 1));
    await shot(tester, '06_now_playing');
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await settle(tester);

    // --- search ------------------------------------------------------------
    await tester.tap(find.text('Recherche').first);
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'riv');
    await waitFor(tester, find.text('Les Rivages'));
    await settle(tester, const Duration(seconds: 1));
    await shot(tester, '07_search');

    // --- playlists in folders --------------------------------------------------
    final container = containerOf(tester);
    final actions = container.read(playlistActionsProvider);
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    final folder = await actions.createFolder('Ambiances $stamp', null);
    final sub = await actions.createFolder('Soirée', folder);
    final pl = await actions.createPlaylist('Calme', sub, [c.state.queue[0].track.id, c.state.queue[1].track.id]);
    await tester.tap(find.text('Playlists').first);
    await waitFor(tester, find.text('Ambiances $stamp'));
    await shot(tester, '08_playlists_root');
    await tester.tap(find.text('Ambiances $stamp'));
    await waitFor(tester, find.text('Soirée'));
    await tester.tap(find.text('Soirée'));
    await waitFor(tester, find.text('Calme'));
    await tester.tap(find.text('Calme'));
    await waitFor(tester, find.text('Track 1 of Blue Hours'));
    await settle(tester, const Duration(seconds: 1));
    await shot(tester, '09_playlist');

    // --- history reached the server --------------------------------------------
    await c.pause();
    await container.read(playReporterProvider).flush();
    final home = await container.read(libraryProvider).home().last;
    expect(home.recentTracks, isNotEmpty, reason: 'plays should be recorded server-side');

    // Clean up the test folder (cascade deletes the sub-folder and playlist).
    await actions.deleteFolder(folder);
    expect(pl.trackCount, 2);
    // ignore: avoid_print
    print('TEST DONE');
    if (holdSeconds > 0) await Future<void>.delayed(const Duration(seconds: holdSeconds));
  });
}
