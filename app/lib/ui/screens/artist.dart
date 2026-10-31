import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/library.dart';
import '../widgets/album_card.dart';
import '../widgets/async_view.dart';

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen(this.id, {super.key});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(artistProvider(id));
    final fav = ref.watch(favoritesProvider.select((f) => f.value?['artists']?.contains(id) ?? false));
    return Scaffold(
      appBar: AppBar(
        title: Text(data.value?.$1.name ?? ''),
        actions: [
          IconButton(
            icon: Icon(fav ? Icons.favorite : Icons.favorite_border),
            onPressed: () => guard(context, () => ref.read(favoritesProvider.notifier).toggle('artists', id)),
          ),
        ],
      ),
      body: AsyncView(
        data,
        onRetry: () => ref.invalidate(artistProvider(id)),
        builder: (d) {
          final (_, albums) = d;
          if (albums.isEmpty) return const Center(child: Text('Apparaît uniquement sur des compilations'));
          return AlbumGrid(albums);
        },
      ),
    );
  }
}
