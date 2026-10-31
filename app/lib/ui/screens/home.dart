import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/library.dart';
import '../../state/playback.dart';
import '../nav.dart';
import '../widgets/album_card.dart';
import '../widgets/async_view.dart';
import '../widgets/track_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accueil'),
        actions: [IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => openSettings(context))],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(homeProvider.future),
        child: AsyncView(home, onRetry: () => ref.invalidate(homeProvider), builder: (h) {
          if (h.recentlyAdded.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 120),
              Center(child: Text('Bibliothèque vide.\nAjoutez de la musique dans le dossier du NAS.', textAlign: TextAlign.center)),
            ]);
          }
          return ListView(children: [
            if (h.recentlyPlayed.isNotEmpty) _Carousel('Récemment écoutés', h.recentlyPlayed),
            _Carousel('Ajouts récents', h.recentlyAdded),
            if (h.recentTracks.isNotEmpty) ...[
              const _Header('Derniers titres écoutés'),
              for (var i = 0; i < h.recentTracks.length && i < 10; i++)
                TrackTile(h.recentTracks[i],
                    onTap: () => ref.read(playbackControllerProvider).playTracks(h.recentTracks, index: i)),
            ],
            const SizedBox(height: 16),
          ]);
        }),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _Carousel extends StatelessWidget {
  const _Carousel(this.title, this.albums);
  final String title;
  final List<Album> albums;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Header(title),
        SizedBox(
          height: 210,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: albums.length,
            itemBuilder: (_, i) => AlbumCard(albums[i], size: 160),
          ),
        ),
      ]);
}
