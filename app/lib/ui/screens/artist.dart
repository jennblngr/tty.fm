import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_repository.dart';
import '../../data/models.dart';
import '../../state/library.dart';
import '../../state/playback.dart';
import '../widgets/album_card.dart';
import '../widgets/async_view.dart';
import '../widgets/tty.dart';

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen(this.id, {super.key});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(artistProvider(id));
    final fav = ref.watch(favoritesProvider.select((f) => f.value?['artists']?.contains(id) ?? false));
    final albums = data.value?.$2 ?? const <Album>[];

    // Plays started here count for the artist in "écouté récemment".
    Future<void> play({required bool shuffle}) => guard(context, () async {
      final tracks = await ref.read(libraryProvider).albumsTracks(albums);
      await ref
          .read(playbackControllerProvider)
          .playTracks(tracks, shuffle: shuffle, contextKind: 'artist', contextId: id);
    });

    return Scaffold(
      appBar: AppBar(
        title: Text((data.value?.$1.name ?? '').toLowerCase()),
        actions: [
          if (albums.isNotEmpty) ...[
            IconButton(tooltip: 'Lire', icon: const Icon(Icons.play_arrow), onPressed: () => play(shuffle: false)),
            IconButton(tooltip: 'Aléatoire', icon: const Icon(Icons.shuffle), onPressed: () => play(shuffle: true)),
          ],
          IconButton(
            tooltip: fav ? 'Retirer des favoris' : 'Ajouter aux favoris',
            icon: HeartIcon(fav, size: 22),
            onPressed: () => guard(context, () => ref.read(favoritesProvider.notifier).toggle('artists', id)),
          ),
        ],
      ),
      body: AsyncView(
        data,
        onRetry: () => ref.invalidate(artistProvider(id)),
        builder: (d) {
          final (_, albums) = d;
          if (albums.isEmpty) return const Center(child: Comment('apparaît uniquement sur des compilations'));
          return AlbumGrid(albums);
        },
      ),
    );
  }
}
