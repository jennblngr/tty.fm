import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../playback/audio_engine.dart';
import '../../state/library.dart';
import '../../state/playback.dart';
import '../dialogs.dart';
import '../format.dart';
import '../nav.dart';
import '../widgets/async_view.dart';
import '../widgets/cover.dart';
import '../widgets/lyrics_view.dart';
import 'devices.dart';

/// Full-screen player with the queue (side by side on wide screens).
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.keyboard_arrow_down), onPressed: () => Navigator.pop(context)),
        title: const Text('En cours de lecture'),
        actions: [
          IconButton(icon: const Icon(Icons.devices), tooltip: 'Appareils', onPressed: () => showDevicesSheet(context)),
          if (!wide)
            IconButton(
              icon: const Icon(Icons.queue_music),
              tooltip: 'File d\'attente',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('File d\'attente')),
                    body: const QueueView(),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: wide
          ? const Row(
              children: [
                Expanded(child: _Player()),
                VerticalDivider(width: 1),
                SizedBox(width: 420, child: QueueView()),
              ],
            )
          : const _Player(),
    );
  }
}

/// Whether the player shows lyrics in place of the cover (kept while the
/// app runs, like a view preference).
class _LyricsShown extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
}

final _lyricsShownProvider = NotifierProvider<_LyricsShown, bool>(_LyricsShown.new);

class _Player extends ConsumerWidget {
  const _Player();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    if (track == null) return const Center(child: Text('Rien en lecture'));
    final st = ref.watch(playbackStateProvider);
    final c = ref.read(playbackControllerProvider);
    final fav = ref.watch(favoritesProvider.select((f) => f.value?['tracks']?.contains(track.id) ?? false));
    final showLyrics = ref.watch(_lyricsShownProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, box) {
        final coverSize = (box.maxWidth - 48).clamp(120.0, (box.maxHeight - 300).clamp(120.0, 520.0));
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showLyrics)
                    SizedBox(width: coverSize, height: coverSize, child: LyricsView(track))
                  else
                    Hero(
                      tag: 'now-cover',
                      child: CoverImage(track.coverId, size: coverSize, radius: 12),
                    ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(track.title, style: text.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                openArtist(context, track.artistId);
                              },
                              child: Text(track.artist, style: text.titleMedium?.copyWith(color: scheme.primary)),
                            ),
                            InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                openAlbum(context, track.albumId);
                              },
                              child: Text(
                                track.album,
                                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? scheme.primary : null),
                        onPressed: () =>
                            guard(context, () => ref.read(favoritesProvider.notifier).toggle('tracks', track.id)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.playlist_add),
                        onPressed: () => addToPlaylist(context, ref, [track]),
                      ),
                      IconButton(
                        icon: Icon(Icons.lyrics_outlined, color: showLyrics ? scheme.primary : null),
                        tooltip: 'Paroles',
                        onPressed: () => ref.read(_lyricsShownProvider.notifier).toggle(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const _SeekBar(),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(Icons.shuffle, color: st.shuffle ? scheme.primary : null),
                        tooltip: 'Aléatoire',
                        onPressed: () => c.setShuffle(!st.shuffle),
                      ),
                      IconButton(iconSize: 36, icon: const Icon(Icons.skip_previous), onPressed: c.previous),
                      IconButton.filled(
                        iconSize: 44,
                        icon: Icon(st.playing ? Icons.pause : Icons.play_arrow),
                        onPressed: c.togglePlay,
                      ),
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(Icons.skip_next),
                        onPressed: st.hasNext ? c.next : null,
                      ),
                      IconButton(
                        icon: Icon(
                          st.repeat == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
                          color: st.repeat != RepeatMode.off ? scheme.primary : null,
                        ),
                        tooltip: 'Répétition',
                        onPressed: c.cycleRepeat,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    [
                      track.format.toUpperCase(),
                      if (track.bitDepth != null && track.sampleRate != null)
                        '${track.bitDepth} bits / ${(track.sampleRate! / 1000).toStringAsFixed(1)} kHz'
                      else if (track.bitrate != null)
                        '${track.bitrate} kb/s',
                    ].join(' · '),
                    style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (st.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(st.error!, style: TextStyle(color: scheme.error, fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeekBar extends ConsumerStatefulWidget {
  const _SeekBar();

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  double? _drag; // milliseconds while dragging

  @override
  Widget build(BuildContext context) {
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final dur = ref.watch(playbackStateProvider.select((s) => s.duration));
    final max = dur.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final value = (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, max);
    final style = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12);
    return Column(
      children: [
        Slider(
          value: value,
          max: max,
          onChanged: (v) => setState(() => _drag = v),
          onChangeEnd: (v) {
            ref.read(playbackControllerProvider).seek(Duration(milliseconds: v.round()));
            setState(() => _drag = null);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(Duration(milliseconds: value.round())), style: style),
              Text(formatDuration(dur), style: style),
            ],
          ),
        ),
      ],
    );
  }
}

/// The play queue: tap to jump, drag to reorder, swipe to remove.
class QueueView extends ConsumerWidget {
  const QueueView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(playbackStateProvider);
    final c = ref.read(playbackControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    if (st.queue.isEmpty) return const Center(child: Text('La file est vide'));
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: st.queue.length,
      onReorderItem: c.move,
      itemBuilder: (context, i) {
        final item = st.queue[i];
        final current = i == st.index;
        return Dismissible(
          key: ValueKey(item.uid),
          direction: current ? DismissDirection.none : DismissDirection.endToStart,
          background: Container(
            color: scheme.errorContainer,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            child: const Icon(Icons.delete_outline),
          ),
          onDismissed: (_) => c.removeAt(i),
          child: ListTile(
            dense: true,
            selected: current,
            leading: CoverImage(item.track.coverId, size: 40),
            title: Text(item.track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(item.track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => c.jumpTo(i),
            trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
          ),
        );
      },
    );
  }
}
