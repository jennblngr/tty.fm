import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/library.dart';
import '../../state/playback.dart';
import '../nav.dart';
import '../widgets/album_card.dart';
import '../widgets/async_view.dart';
import '../widgets/cover.dart';
import '../widgets/track_tile.dart';

/// Artists / Albums / Tracks. Whole lists are loaded once and cached, so
/// scrolling and the local filter are instant.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bibliothèque'),
          bottom: const TabBar(tabs: [Tab(text: 'Artistes'), Tab(text: 'Albums'), Tab(text: 'Titres')]),
        ),
        body: const TabBarView(children: [_Artists(), _Albums(), _Tracks()]),
      ),
    );
  }
}

class _Artists extends ConsumerWidget {
  const _Artists();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);
    return AsyncView(artists, onRetry: () => ref.invalidate(artistsProvider), builder: (list) {
      return RefreshIndicator(
        onRefresh: () => ref.refresh(artistsProvider.future),
        child: ListView.builder(
          itemExtent: 64,
          itemCount: list.length,
          itemBuilder: (_, i) {
            final a = list[i];
            return ListTile(
              leading: CoverImage(a.coverId, size: 44, radius: 22, icon: Icons.person),
              title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${a.albumCount} album${a.albumCount > 1 ? 's' : ''}'),
              onTap: () => openArtist(context, a.id),
            );
          },
        ),
      );
    });
  }
}

class _Albums extends ConsumerStatefulWidget {
  const _Albums();

  @override
  ConsumerState<_Albums> createState() => _AlbumsState();
}

class _AlbumsState extends ConsumerState<_Albums> {
  String _sort = 'added';

  @override
  Widget build(BuildContext context) {
    final albums = ref.watch(albumsProvider(_sort));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'added', label: Text('Récents')),
            ButtonSegment(value: 'name', label: Text('A-Z')),
            ButtonSegment(value: 'year', label: Text('Année')),
          ],
          selected: {_sort},
          onSelectionChanged: (s) => setState(() => _sort = s.first),
        ),
      ),
      Expanded(
        child: AsyncView(albums, onRetry: () => ref.invalidate(albumsProvider(_sort)), builder: (list) {
          return RefreshIndicator(onRefresh: () => ref.refresh(albumsProvider(_sort).future), child: AlbumGrid(list));
        }),
      ),
    ]);
  }
}

class _Tracks extends ConsumerWidget {
  const _Tracks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(tracksProvider);
    return AsyncView(tracks, onRetry: () => ref.invalidate(tracksProvider), builder: (list) {
      return Column(children: [
        ListTile(
          leading: const Icon(Icons.shuffle),
          title: Text('Tout en aléatoire (${list.length})'),
          onTap: () => ref.read(playbackControllerProvider).playTracks(list, shuffle: true, contextKind: 'library'),
        ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(tracksProvider.future),
            child: ListView.builder(
              itemExtent: 60,
              itemCount: list.length,
              itemBuilder: (_, i) => TrackTile(list[i],
                  onTap: () => ref.read(playbackControllerProvider).playTracks(list, index: i, contextKind: 'library')),
            ),
          ),
        ),
      ]);
    });
  }
}
