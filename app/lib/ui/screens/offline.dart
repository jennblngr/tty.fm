import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../offline/downloads.dart';
import '../../state/playback.dart';
import '../format.dart';
import '../widgets/cover.dart';
import '../widgets/download_button.dart';
import '../widgets/track_tile.dart';

String formatBytes(int b) {
  if (b < 1 << 20) return '${(b / 1024).toStringAsFixed(0)} Ko';
  if (b < 1 << 30) return '${(b / (1 << 20)).toStringAsFixed(0)} Mo';
  return '${(b / (1 << 30)).toStringAsFixed(1)} Go';
}

/// Downloaded albums, playlists and favourites. Works without a network:
/// everything comes from the offline index.
class OfflineList extends ConsumerWidget {
  const OfflineList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(downloadsProvider);
    final scheme = Theme.of(context).colorScheme;
    if (s.collections.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Rien de téléchargé.\nUtilisez ⤓ sur un album, une playlist ou vos favoris pour les écouter sans réseau.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final cols = s.collections.values.toList()..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return ListView(
      children: [
        const OfflineStatusTile(),
        for (final c in cols)
          () {
            final (done, total) = s.progress(c.kind, c.id);
            return ListTile(
              leading: c.kind == 'favorites'
                  ? CircleAvatar(backgroundColor: scheme.primaryContainer, child: const Icon(Icons.favorite))
                  : c.kind == 'playlist'
                  ? PlaylistCover(c.coverIds, size: 48)
                  : CoverImage(c.coverIds.firstOrNull, size: 48),
              title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  switch (c.kind) {
                    'album' => 'Album${c.subtitle.isEmpty ? '' : ' · ${c.subtitle}'}',
                    'playlist' => 'Playlist',
                    _ => 'Favoris',
                  },
                  done == total ? '$total titres' : '$done / $total titres',
                ].join(' · '),
              ),
              trailing: DownloadButton(kind: c.kind, id: c.id, title: c.title, tracks: const []),
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => OfflineCollectionScreen(c.key))),
            );
          }(),
      ],
    );
  }
}

/// Current download activity and storage used.
class OfflineStatusTile extends ConsumerWidget {
  const OfflineStatusTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(downloadsProvider);
    final active = s.active;
    final String line;
    if (active != null) {
      line = 'Téléchargement : ${active.title} (${s.pending.length} en attente)';
    } else if (s.waitingForWifi) {
      line = '${s.pending.length} titre(s) en attente du Wi-Fi';
    } else if (s.pending.isNotEmpty) {
      line = '${s.pending.length} titre(s) en attente';
    } else {
      line = 'À jour';
    }
    return Column(
      children: [
        ListTile(
          dense: true,
          leading: Icon(active != null ? Icons.downloading : Icons.offline_pin_outlined),
          title: Text(line, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${s.tracks.length} titres · ${formatBytes(s.totalBytes)}${s.error != null ? ' · ${s.error}' : ''}',
          ),
        ),
        if (active != null) LinearProgressIndicator(value: s.activeProgress, minHeight: 2),
      ],
    );
  }
}

class OfflineCollectionScreen extends ConsumerWidget {
  const OfflineCollectionScreen(this.collectionKey, {super.key});
  final String collectionKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(downloadsProvider);
    final c = s.collections[collectionKey];
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Plus disponible hors ligne')),
      );
    }
    final tracks = s.tracksOf(c);
    final pc = ref.read(playbackControllerProvider);
    final totalMs = tracks.fold<int>(0, (a, t) => a + t.durationMs);
    return Scaffold(
      appBar: AppBar(
        title: Text(c.title),
        actions: [DownloadButton(kind: c.kind, id: c.id, title: c.title, tracks: const [])],
      ),
      body: ListView(
        children: [
          ListTile(
            title: Text(formatCountDuration(tracks.length, totalMs)),
            subtitle: tracks.length < c.trackIds.length
                ? Text('${c.trackIds.length - tracks.length} titre(s) pas encore téléchargé(s)')
                : null,
            trailing: Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Lire'),
                  onPressed: tracks.isEmpty
                      ? null
                      : () => pc.playTracks(tracks, shuffle: false, contextKind: c.kind, contextId: c.id),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Aléatoire'),
                  onPressed: tracks.isEmpty
                      ? null
                      : () => pc.playTracks(tracks, shuffle: true, contextKind: c.kind, contextId: c.id),
                ),
              ],
            ),
          ),
          for (var i = 0; i < tracks.length; i++)
            TrackTile(
              tracks[i],
              showCover: c.kind != 'album',
              onTap: () => pc.playTracks(tracks, index: i, contextKind: c.kind, contextId: c.id),
            ),
        ],
      ),
    );
  }
}
