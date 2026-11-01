import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/library.dart';
import '../../state/playback.dart';
import '../format.dart';
import '../widgets/async_view.dart';
import '../theme.dart';
import '../widgets/cover.dart';
import '../widgets/tty.dart';
import '../widgets/download_button.dart';
import '../widgets/track_tile.dart';

/// Playlist detail: play / shuffle, drag to reorder, remove entries.
class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen(this.id, {super.key});
  final int id;

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  /// Local order while a reorder is in flight, so the list does not jump
  /// back before the server confirms.
  List<PlaylistEntry>? _optimistic;

  int get id => widget.id;

  Future<void> _reorder(List<PlaylistEntry> entries, int from, int to) async {
    if (from == to) return;
    final next = [...entries];
    next.insert(to, next.removeAt(from));
    setState(() => _optimistic = next);
    await guard(context, () => ref.read(playlistActionsProvider).moveEntry(id, entries[from].entryId, to));
    if (mounted) setState(() => _optimistic = null);
  }

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(playlistTreeProvider);
    final playlist = tree.value?.allPlaylists.where((p) => p.id == id).firstOrNull;
    final entries = ref.watch(playlistTracksProvider(id));
    final c = ref.read(playbackControllerProvider);
    final tty = Tty.of(context);

    return Scaffold(
      appBar: AppBar(
        actions: [
          DownloadButton(
            kind: 'playlist',
            id: id,
            title: playlist?.name ?? '',
            coverIds: playlist?.coverIds ?? const [],
            tracks: entries.value == null ? null : [for (final e in entries.value!) e.track],
          ),
        ],
      ),
      body: AsyncView(
        entries,
        onRetry: () => ref.invalidate(playlistTracksProvider(id)),
        builder: (fresh) {
          final list = _optimistic ?? fresh;
          final tracks = [for (final e in list) e.track];
          final totalMs = tracks.fold<int>(0, (s, t) => s + t.durationMs);
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      PlaylistCover(playlist?.coverIds ?? const [], size: 96, label: playlist?.name ?? '', seed: id),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '\$ ',
                                    style: TextStyle(color: tty.green),
                                  ),
                                  const TextSpan(text: 'playlist'),
                                ],
                              ),
                            ),
                            Text(
                              playlist?.name ?? '',
                              style: TextStyle(color: tty.accentFor(id), fontSize: 20, fontWeight: FontWeight.w700),
                            ),
                            Comment(formatCountDuration(tracks.length, totalMs).toLowerCase()),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton.icon(
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Lire'),
                                  onPressed: tracks.isEmpty
                                      ? null
                                      : () => c.playTracks(
                                          tracks,
                                          shuffle: false,
                                          contextKind: 'playlist',
                                          contextId: id,
                                        ),
                                ),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.shuffle),
                                  label: const Text('Aléatoire'),
                                  onPressed: tracks.isEmpty
                                      ? null
                                      : () =>
                                            c.playTracks(tracks, shuffle: true, contextKind: 'playlist', contextId: id),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (list.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text('Playlist vide.\nAjoutez des titres depuis leur menu ⋮', textAlign: TextAlign.center),
                  ),
                ),
              SliverReorderableList(
                itemCount: list.length,
                onReorderItem: (from, to) => _reorder(list, from, to),
                itemBuilder: (context, i) {
                  final e = list[i];
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(e.entryId),
                    index: i,
                    child: Material(
                      type: MaterialType.transparency,
                      child: TrackTile(
                        e.track,
                        onTap: () => c.playTracks(tracks, index: i, contextKind: 'playlist', contextId: id),
                        trailing: ReorderableDragStartListener(
                          index: i,
                          child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle, size: 20)),
                        ),
                        extraMenu: [
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: () =>
                                guard(context, () => ref.read(playlistActionsProvider).removeEntry(id, e.entryId)),
                            child: const ListTile(
                              leading: Icon(Icons.remove_circle_outline),
                              title: Text('Retirer de la playlist'),
                              dense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}
