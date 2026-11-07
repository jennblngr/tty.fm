import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/library.dart';
import '../../state/playback.dart';
import '../dialogs.dart';
import '../format.dart';
import '../nav.dart';
import '../widgets/async_view.dart';
import '../theme.dart';
import '../widgets/cover.dart';
import '../widgets/tty.dart';
import '../widgets/download_button.dart';
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
          DownloadButton(
            kind: 'album',
            id: id,
            title: data.value?.$1.title ?? '',
            subtitle: data.value?.$1.artist ?? '',
            coverIds: [?data.value?.$1.coverId],
            tracks: data.value?.$2,
          ),
          IconButton(
            tooltip: fav ? 'Retirer des favoris' : 'Ajouter aux favoris',
            icon: HeartIcon(fav, size: 22),
            onPressed: () => guard(context, () => ref.read(favoritesProvider.notifier).toggle('albums', id)),
          ),
        ],
      ),
      body: AsyncView(
        data,
        onRetry: () => ref.invalidate(albumProvider(id)),
        builder: (d) {
          final (album, all) = d;
          final tracks = visibleTracks(ref, all);
          final multiDisc = tracks.map((t) => t.discNo ?? 1).toSet().length > 1;
          final tty = Tty.of(context);
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
                child: Wrap(
                  spacing: 20,
                  runSpacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    CoverImage(album.coverId, size: 200, radius: 8, label: album.artist, seed: album.id),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
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
                                const TextSpan(text: 'album'),
                              ],
                            ),
                          ),
                          Text(
                            album.title.toLowerCase(),
                            style: TextStyle(color: tty.accentFor(album.id), fontSize: 22, fontWeight: FontWeight.w700),
                          ),
                          InkWell(
                            onTap: () => openArtist(context, album.artistId),
                            child: Text(album.artist.toLowerCase(), style: TextStyle(color: tty.text)),
                          ),
                          Comment(
                            [
                              if (album.year != null) '${album.year}',
                              if (album.genre != null) album.genre!.toLowerCase(),
                              formatCountDuration(album.trackCount, album.durationMs).toLowerCase(),
                            ].join(' · '),
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
                    child: TtySection('disque ${tracks[i].discNo ?? 1}', glyph: '◉', color: tty.peach),
                  ),
                TrackTile(
                  tracks[i],
                  showCover: false,
                  onTap: () => c.playTracks(tracks, index: i, contextKind: 'album', contextId: id),
                ),
              ],
              if (tracks.isEmpty && all.isNotEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Comment('tous les titres sont archivés')),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
