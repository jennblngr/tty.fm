import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/library.dart';
import '../../state/playback.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/album_card.dart';
import '../widgets/async_view.dart';
import '../widgets/download_button.dart';
import '../widgets/track_tile.dart';
import '../widgets/tty.dart';

/// "♥ titres likés": favourite tracks (playable, downloadable) and albums.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoriteListsProvider);
    final c = Tty.of(context);
    final pc = ref.read(playbackControllerProvider);
    return Scaffold(
      appBar: AppBar(),
      body: AsyncView(
        favs,
        onRetry: () => ref.invalidate(favoriteListsProvider),
        builder: (data) {
          final (tracks, albums) = data;
          final totalMs = tracks.fold<int>(0, (s, t) => s + t.durationMs);
          return TtyPage(
            gap: 20,
            onRefresh: () => ref.refresh(favoriteListsProvider.future),
            children: [
              TtyPrompt(
                'cat ~/likés',
                comment: tracks.isEmpty && albums.isEmpty
                    ? 'aucun favori : utilise ♡ sur un titre ou un album.'
                    : formatCountDuration(tracks.length, totalMs).toLowerCase(),
                trailing: DownloadButton(kind: 'favorites', id: 0, title: 'Titres likés', tracks: tracks),
              ),
              if (tracks.isNotEmpty)
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('lire'),
                      onPressed: () => pc.playTracks(tracks, shuffle: false, contextKind: 'favorites'),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.shuffle, size: 18),
                      label: const Text('aléatoire'),
                      onPressed: () => pc.playTracks(tracks, shuffle: true, contextKind: 'favorites'),
                    ),
                  ],
                ),
              if (albums.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TtySection('albums', glyph: '◉', color: c.mauve),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 210,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: albums.length,
                        itemBuilder: (_, i) => AlbumCard(albums[i], size: 160),
                      ),
                    ),
                  ],
                ),
              if (tracks.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TtySection('titres', glyph: '♥', color: c.red, ruled: true),
                    for (var i = 0; i < tracks.length; i++)
                      TrackTile(
                        tracks[i],
                        leadingNumber: i + 1,
                        onTap: () => pc.playTracks(tracks, index: i, contextKind: 'favorites'),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
