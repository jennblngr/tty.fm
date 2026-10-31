import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_info.dart';
import 'core/api_client.dart';
import 'core/json_cache.dart';
import 'core/network.dart';
import 'core/settings.dart';
import 'core/session.dart';
import 'playback/system_audio.dart';
import 'state/playback.dart';
import 'offline/downloads.dart';
import 'state/remote.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final cache = await JsonCache.open();
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs), jsonCacheProvider.overrideWithValue(cache)],
  );

  if (SystemAudioHandler.supported) {
    // The artwork URL carries the token: load it before the restored queue
    // publishes its first media item.
    await container.read(sessionProvider.future);
    final controller = container.read(playbackControllerProvider);
    try {
      final handler = await AudioService.init(
        builder: () => SystemAudioHandler(controller, (t) {
          if (t.coverId == null) return null;
          final api = container.read(apiProvider);
          return Uri.parse(api.url('/covers/${t.coverId}?size=800&token=${container.read(tokenProvider)}'));
        }),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'dev.selfstream.playback',
          androidNotificationChannelName: '$appDisplayName playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
      // Server address (LAN probe done, network changed) or token changed:
      // the artwork URL must follow.
      container.listen(routeProvider, (_, _) => handler.refreshArtwork());
      container.listen(tokenProvider, (_, _) => handler.refreshArtwork());
    } catch (e) {
      debugPrint('audio_service unavailable: $e');
    }
  }

  container.read(downloadsProvider); // loads the offline index
  // Live hub (sync and remote control). Listened, not just read, so it is
  // rebuilt when the server address or the token changes.
  container.listen(liveSyncProvider, (_, _) {});

  runApp(UncontrolledProviderScope(container: container, child: const SelfstreamApp()));
}
