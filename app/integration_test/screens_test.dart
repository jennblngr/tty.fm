// Read-only visual tour: opens each main screen at desktop and phone sizes,
// in dark and light, and saves screenshots. Uses the session already stored
// on the machine (nothing is played, created or changed).
//
//   cd app && flutter test integration_test/screens_test.dart -d macos

import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ttyfm/main.dart' as app;
import 'package:ttyfm/ui/widgets/mini_player.dart';

Future<void> settle(WidgetTester tester, [Duration d = const Duration(milliseconds: 1500)]) async {
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('visual tour', (tester) async {
    await app.main();
    await settle(tester, const Duration(seconds: 4));

    Future<void> tour(String prefix, {required bool phone}) async {
      // Tab labels: "accueil" on phones, "> accueil" / "  accueil" in the sidebar.
      Future<void> tab(String label) async {
        await tester.tap(
          find.byWidgetPredicate((w) => w is Text && w.data?.replaceFirst('>', '').trim() == label).last,
        );
        await settle(tester);
      }

      await tab('accueil');
      await shot(tester, '${prefix}_1_accueil');
      await tab('recherche');
      await shot(tester, '${prefix}_2_recherche');
      await tester.enterText(find.byType(TextField).first, 'adele');
      await settle(tester, const Duration(seconds: 2));
      await shot(tester, '${prefix}_3_recherche_adele');
      await tester.tap(find.byIcon(Icons.clear).first);
      await tab('biblio');
      await shot(tester, '${prefix}_4_biblio');
      await tester.tap(find.text('[albums]'));
      await settle(tester);
      await shot(tester, '${prefix}_5_albums');
      await tester.tap(find.text('[playlists]'));
      await tab('stats');
      await settle(tester);
      await shot(tester, '${prefix}_6_stats');
      // Full player (the restored queue gives a current track, paused).
      final player = phone ? find.byType(MiniPlayer) : find.text('[paroles]');
      if (player.evaluate().isNotEmpty) {
        await tester.tap(player.first);
        await settle(tester, const Duration(seconds: 2));
        await shot(tester, '${prefix}_7_lecteur');
        await tester.tap(find.text(phone ? '[fermer]' : '[réduire]'));
        await settle(tester);
      }
    }

    for (final dark in [true, false]) {
      tester.platformDispatcher.platformBrightnessTestValue = dark ? Brightness.dark : Brightness.light;
      final theme = dark ? 'dark' : 'light';
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 1000);
      await settle(tester);
      await tour('desktop_$theme', phone: false);
      if (!dark) continue; // phone tour in dark only
      tester.view.physicalSize = const Size(390, 844);
      await settle(tester);
      await tour('phone_$theme', phone: true);
    }
    tester.view.reset();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });
}
