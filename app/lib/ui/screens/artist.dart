import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/library.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: Text((data.value?.$1.name ?? '').toLowerCase()),
        actions: [
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
