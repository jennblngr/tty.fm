import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../nav.dart';
import 'cover.dart';

/// Square cover with title and artist, for grids and carousels.
class AlbumCard extends StatelessWidget {
  const AlbumCard(this.album, {super.key, this.size = 150});

  final Album album;
  final double size;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => openAlbum(context, album.id),
      child: SizedBox(
        width: size,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CoverImage(album.coverId, size: size - 8, radius: 8),
            const SizedBox(height: 6),
            Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
            Text(album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

/// Responsive grid of albums.
class AlbumGrid extends StatelessWidget {
  const AlbumGrid(this.albums, {super.key, this.shrinkWrap = false});

  final List<Album> albums;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        childAspectRatio: 0.76,
      ),
      itemCount: albums.length,
      itemBuilder: (_, i) => LayoutBuilder(builder: (_, c) => AlbumCard(albums[i], size: c.maxWidth)),
    );
  }
}
