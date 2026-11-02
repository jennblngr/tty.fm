// End-to-end test of the real app against a running server.
//
//   cd server && TTYFM_MUSIC_DIR=../data/dev-music TTYFM_DATA_DIR=../data/dev-data \
//     TTYFM_ADMIN_PASSWORD=devpass TTYFM_LISTEN=127.0.0.1:4533 ./bin/ttyfm
//   cd app && flutter test integration_test -d macos \
//     --dart-define=SERVER=127.0.0.1:4533 --dart-define=PASSWORD=devpass
//
// Screenshots are written to the app's support directory (path printed).

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ttyfm/core/session.dart';
import 'package:ttyfm/data/library_repository.dart';
import 'package:ttyfm/main.dart' as app;
import 'package:ttyfm/offline/downloads.dart';
import 'package:ttyfm/state/library.dart';
import 'package:ttyfm/state/playback.dart';
import 'package:ttyfm/state/remote.dart';
import 'package:ttyfm/state/search.dart';
import 'package:ttyfm/ui/widgets/mini_player.dart';

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

/// Pumps until [cond] holds.
Future<void> waitUntil(
  WidgetTester tester,
  bool Function() cond,
  String what, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) {
      await shot(tester, 'timeout');
      throw TestFailure('Timed out waiting for $what');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
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
  // ignore: invalid_use_of_protected_member
  final layer = view.layer! as OffsetLayer; // debugLayer only exists in debug builds
  final image = await layer.toImage(view.paintBounds, pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/screenshots');
  await dir.create(recursive: true);
  final f = File('${dir.path}/$name.png');
  await f.writeAsBytes(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('SCREENSHOT ${f.path}');
}

/// Types into a text field through its controller and onChanged (the test
/// text input is not available in profile builds).
Future<void> typeInto(WidgetTester tester, Finder field, String text) async {
  final tf = tester.widget<TextField>(field);
  tf.controller!.text = text;
  tf.onChanged?.call(text);
  await tester.pump();
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login, browse, play, playlists', (tester) async {
    await app.main();
    await settle(tester, const Duration(seconds: 2));

    // Tab labels: "accueil" on phones, "> accueil" / "  accueil" in the sidebar.
    Future<void> tab(String label) async {
      await tester.tap(find.byWidgetPredicate((w) => w is Text && w.data?.replaceFirst('>', '').trim() == label).last);
      await settle(tester);
    }

    Finder rich(String text) => find.textContaining(text, findRichText: true);

    // --- login (skipped if a token is already stored) -----------------------
    if (find.text('Se connecter').evaluate().isNotEmpty) {
      await shot(tester, '01_login');
      // Through the session logic: typing in fields is unreliable in profile
      // builds (the login form itself is simple and covered by earlier runs).
      await containerOf(tester)
          .read(sessionProvider.notifier)
          .login(remoteUrl: server, username: 'admin', password: password);
    }
    await waitFor(tester, rich('ajouts récents'), timeout: const Duration(seconds: 40)); // cold start on emulators
    await settle(tester, const Duration(seconds: 2)); // covers
    await shot(tester, '02_home');

    // --- library: albums grid, then album page ------------------------------
    await tab('biblio');
    await tester.tap(find.text('[albums]'));
    await settle(tester, const Duration(seconds: 2));
    await shot(tester, '03_albums');
    await tester.tap(find.text('Blue Hours').first);
    await waitFor(tester, find.text('Lire'));
    await settle(tester, const Duration(seconds: 1));
    await shot(tester, '04_album');

    // --- playback through media_kit ------------------------------------------
    final container = containerOf(tester);
    final c = container.read(playbackControllerProvider);
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

    // Full player, with the devices button.
    await tester.tap(find.byType(MiniPlayer));
    await waitFor(tester, find.text('[fermer]'));
    await settle(tester, const Duration(seconds: 1));
    await shot(tester, '06_now_playing');
    await tester.tap(find.text('[fermer]'));
    await settle(tester);

    // --- search ------------------------------------------------------------
    await tab('recherche');
    await typeInto(tester, find.byType(TextField).first, 'riv');
    await waitFor(tester, find.text('Marée Haute'));
    await settle(tester, const Duration(seconds: 1));
    await shot(tester, '07_search');

    // --- playlists in folders (in biblio) -------------------------------------
    final actions = container.read(playlistActionsProvider);
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    final folder = await actions.createFolder('Ambiances $stamp', null);
    final sub = await actions.createFolder('Soirée', folder);
    final pl = await actions.createPlaylist('Calme', sub, [c.state.queue[0].track.id, c.state.queue[1].track.id]);
    await tab('biblio');
    await tab('biblio'); // back to the library root
    await tester.tap(find.text('[playlists]'));
    await waitFor(tester, find.text('Ambiances $stamp/'));
    await shot(tester, '08_playlists_root');
    await tester.tap(find.text('Ambiances $stamp/'));
    await waitFor(tester, find.text('Soirée/'));
    await tester.tap(find.text('Soirée/'));
    await waitFor(tester, find.text('Calme'));
    await tester.tap(find.text('Calme'));
    await waitFor(tester, find.text('Track 1 of Blue Hours'));
    await settle(tester, const Duration(seconds: 1));
    await shot(tester, '09_playlist');

    // --- another device: live sync and remote control -------------------------
    final other = Dio(BaseOptions(baseUrl: 'http://$server/api/v1'));
    final login2 = await other.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'username': 'admin', 'password': password, 'device_name': 'Autre appareil', 'platform': 'linux'},
    );
    final token2 = login2.data!['token'] as String;
    other.options.headers['Authorization'] = 'Bearer $token2';
    // A playlist created elsewhere shows up here without refreshing.
    final remotePl = await other.post<Map<String, dynamic>>('/playlists', data: {'name': 'Depuis ailleurs $stamp'});
    await waitUntil(
      tester,
      () =>
          container.read(playlistTreeProvider).value?.allPlaylists.any((p) => p.name == 'Depuis ailleurs $stamp') ??
          false,
      'live playlist sync',
    );
    // The other device joins the live hub and sends us a command.
    final ws = await WebSocket.connect('ws://$server/api/v1/ws', headers: {'Authorization': 'Bearer $token2'});
    final inbox = ws.map((m) => jsonDecode(m as String) as Map<String, dynamic>).asBroadcastStream();
    final hello = await inbox.firstWhere((m) => m['type'] == 'hello');
    final me = (hello['devices'] as List).cast<Map<String, dynamic>>().firstWhere((d) => d['platform'] != 'linux');
    await waitUntil(
      tester,
      () => container.read(remoteDevicesProvider).devices.values.any((d) => d.name == 'Autre appareil'),
      'presence',
    );
    await tester.tap(find.byType(MiniPlayer));
    await waitFor(tester, find.text('⌁ ce tél.'));
    await tester.tap(find.text('⌁ ce tél.'));
    await waitFor(tester, find.text('Autre appareil'));
    await settle(tester);
    await shot(tester, '10_devices');
    Navigator.of(tester.element(find.text('Autre appareil')), rootNavigator: true).pop(); // close the sheet
    await settle(tester);
    await c.pause();
    await settle(tester);
    ws.add(jsonEncode({'type': 'command', 'target': me['id'], 'action': 'play'}));
    await waitUntil(tester, () => c.state.playing, 'remote play command');
    final st = await inbox.firstWhere((m) => m['type'] == 'state' && (m['state'] as Map)['playing'] == true);
    expect(st['device_id'], me['id']);
    await c.pause();
    await ws.close();

    // --- lyrics (synced .lrc next to track 1 of Blue Hours) --------------------
    await c.jumpTo(0);
    await waitUntil(tester, () => c.state.current?.title == 'Track 1 of Blue Hours', 'track 1');
    await waitFor(tester, find.textContaining('First line of Blue Hours'));
    await settle(tester, const Duration(seconds: 4)); // let the highlight move on
    await shot(tester, '11_lyrics');
    await c.pause();
    await tester.tap(find.text('[fermer]'));
    await settle(tester);

    // --- offline: download the album, then play from the local files ----------
    await tab('biblio');
    await tab('biblio');
    await tester.tap(find.text('[albums]'));
    await settle(tester);
    await tester.tap(find.text('Blue Hours').first);
    await waitFor(tester, find.byTooltip('Télécharger'));
    await tester.tap(find.byTooltip('Télécharger'));
    final dm = container.read(downloadsProvider.notifier);
    final blueHours = c.state.queue[0].track.albumId;
    await waitUntil(
      tester,
      () => container.read(downloadsProvider).status('album', blueHours) == CollectionStatus.done,
      'album download',
      timeout: const Duration(seconds: 60),
    );
    final local = dm.pathFor(c.state.queue[0].track.id);
    expect(local, isNotNull);
    expect(File(local!).lengthSync(), greaterThan(10000));
    expect(c.sourceFor(c.state.queue[0].track).url, local, reason: 'playback uses the offline copy');
    await settle(tester);
    await shot(tester, '12_album_downloaded');
    await tab('biblio');
    await tester.tap(find.text('[playlists]'));
    await settle(tester);
    await tester.tap(find.text('hors-ligne'));
    await waitFor(tester, find.textContaining('4 titres'));
    await shot(tester, '13_offline');
    await tester.pageBack();
    await settle(tester);

    // --- search filters ---------------------------------------------------------
    await tab('recherche');
    await tester.tap(find.byIcon(Icons.clear)); // clears the previous "riv" query
    await settle(tester);
    await tester.tap(find.text('genre ▾'));
    await settle(tester);
    await tester.tap(find.text('jazz (4)'));
    await waitFor(tester, find.text('Track 4 of Blue Hours'));
    expect(find.text('Track 1 of Midnight Drive'), findsNothing);
    await settle(tester);
    await shot(tester, '14_search_filter');
    await tester.tap(find.text('[effacer]'));
    await settle(tester);

    dm.remove('album', blueHours);
    await other.delete<void>('/playlists/${remotePl.data!['id']}');
    await other.post<void>('/auth/logout');

    // --- history reached the server --------------------------------------------
    await c.pause();
    await container.read(playReporterProvider).flush();
    final home = await container.read(libraryProvider).home().last;
    expect(home.recentlyPlayed, isNotEmpty, reason: 'plays should be recorded server-side');

    // --- stats from that history -------------------------------------------------
    container.invalidate(statsProvider);
    await tab('stats');
    await waitFor(tester, rich('top artistes'));
    await settle(tester, const Duration(seconds: 1));
    await shot(tester, '15_stats');

    // Clean up the test folder (cascade deletes the sub-folder and playlist).
    await actions.deleteFolder(folder);
    expect(pl.trackCount, 2);

    // --- visual tour: desktop layout and light theme, rendered off-screen --------
    for (final (name, size, dark) in const [
      ('desktop_dark', Size(1440, 1000), true),
      ('desktop_light', Size(1440, 1000), false),
      ('phone_light', Size(412, 915), false),
    ]) {
      tester.platformDispatcher.platformBrightnessTestValue = dark ? Brightness.dark : Brightness.light;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await settle(tester);
      for (final t in const ['accueil', 'recherche', 'biblio', 'stats']) {
        await tab(t);
        await settle(tester, const Duration(seconds: 1));
        await shot(tester, '${name}_$t');
      }
      await tester.tap(size.width >= 900 ? find.text('[paroles]') : find.byType(MiniPlayer));
      await settle(tester, const Duration(seconds: 2));
      await shot(tester, '${name}_lecteur');
      await tester.tap(find.text(size.width >= 900 ? '[réduire]' : '[fermer]'));
      await settle(tester);
    }
    tester.view.reset();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();

    // ignore: avoid_print
    print('TEST DONE');
    if (holdSeconds > 0) await Future<void>.delayed(const Duration(seconds: holdSeconds));
  });
}
