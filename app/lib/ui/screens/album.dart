import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/library.dart';
import '../../state/playback.dart';
import '../dialogs.dart';
import '../format.dart';
import '../nav.dart';
import '../widgets/async_view.dart';
import '../widgets/cover.dart';
import '../widgets/track_tile.dart';

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen(this.id, {super.key});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(albumProvider(id));
    final fav = ref.watch(favoritesProvider.select((f) => f.value?['albums']?.contains(id) ?? false));
    final c = ref.read(playbackControllerProvider);
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(fav ? Icons.favorite : Icons.favorite_border),
            onPressed: () => guard(context, () => ref.read(favoritesProvider.notifier).toggle('albums', id)),
          ),
        ],
      ),
      body: AsyncView(
        data,
        onRetry: () => ref.invalidate(albumProvider(id)),
        builder: (d) {
          final (album, tracks) = d;
          final multiDisc = tracks.map((t) => t.discNo ?? 1).toSet().length > 1;
          final text = Theme.of(context).textTheme;
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 20,
                  runSpacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    CoverImage(album.coverId, size: 200, radius: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(album.title, style: text.headlineSmall),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () => openArtist(context, album.artistId),
                            child: Text(
                              album.artist,
                              style: text.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (album.year != null) '${album.year}',
                              if (album.genre != null) album.genre!,
                              formatCountDuration(album.trackCount, album.durationMs),
                            ].join(' · '),
                            style: text.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              FilledButton.icon(
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Lire'),
                                onPressed: () =>
                                    c.playTracks(tracks, shuffle: false, contextKind: 'album', contextId: id),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.shuffle),
                                label: const Text('Aléatoire'),
                                onPressed: () =>
                                    c.playTracks(tracks, shuffle: true, contextKind: 'album', contextId: id),
                              ),
                              PopupMenuButton<VoidCallback>(
                                onSelected: (a) => a(),
                                itemBuilder: (_) => [
                                  PopupMenuItem(value: () => c.playNext(tracks), child: const Text('Lire ensuite')),
                                  PopupMenuItem(
                                    value: () => c.addToQueue(tracks),
                                    child: const Text('Ajouter à la file'),
                                  ),
                                  PopupMenuItem(
                                    value: () => addToPlaylist(context, ref, tracks),
                                    child: const Text('Ajouter à une playlist…'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < tracks.length; i++) ...[
                if (multiDisc && (i == 0 || tracks[i].discNo != tracks[i - 1].discNo))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('Disque ${tracks[i].discNo ?? 1}', style: text.labelLarge),
                  ),
                TrackTile(
                  tracks[i],
                  showCover: false,
                  onTap: () => c.playTracks(tracks, index: i, contextKind: 'album', contextId: id),
                ),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
