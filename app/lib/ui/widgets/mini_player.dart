import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/playback.dart';
import '../../state/remote.dart';
import '../screens/devices.dart';
import '../nav.dart';
import 'cover.dart';

/// Compact player shown under every screen.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    if (track == null) {
      final elsewhere = ref.watch(remoteDevicesProvider.select((r) => r.activeElsewhere));
      return elsewhere == null ? const SizedBox.shrink() : RemoteMiniBar(elsewhere);
    }
    final playing = ref.watch(playbackStateProvider.select((s) => s.playing));
    final buffering = ref.watch(playbackStateProvider.select((s) => s.buffering));
    final c = ref.read(playbackControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: InkWell(
        onTap: () => openNowPlaying(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _ThinProgress(),
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  Hero(tag: 'now-cover', child: CoverImage(track.coverId, size: 44)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.skip_previous), onPressed: c.previous, tooltip: 'Précédent'),
                  SizedBox(
                    width: 48,
                    child: buffering && playing
                        ? const Center(
                            child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                            onPressed: c.togglePlay,
                            tooltip: playing ? 'Pause' : 'Lecture',
                          ),
                  ),
                  IconButton(icon: const Icon(Icons.skip_next), onPressed: c.next, tooltip: 'Suivant'),
                  IconButton(
                    icon: const Icon(Icons.devices),
                    onPressed: () => showDevicesSheet(context),
                    tooltip: 'Appareils',
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinProgress extends ConsumerWidget {
  const _ThinProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final dur = ref.watch(playbackStateProvider.select((s) => s.duration));
    final v = dur.inMilliseconds == 0 ? 0.0 : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
    return LinearProgressIndicator(value: v, minHeight: 2);
  }
}
