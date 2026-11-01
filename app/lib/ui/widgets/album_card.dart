import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../nav.dart';
import '../theme.dart';
import 'cover.dart';
import 'tty.dart';

/// Square cover with title and artist, for grids and carousels.
class AlbumCard extends StatelessWidget {
  const AlbumCard(this.album, {super.key, this.size = 150});

  final Album album;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => openAlbum(context, album.id),
      child: SizedBox(
        width: size,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverImage(album.coverId, size: size - 8, radius: 6, label: album.artist, seed: album.id),
              const SizedBox(height: 8),
              Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.accentFor(album.id)),
              ),
              Comment(album.artist, maxLines: 1),
            ],
          ),
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
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190, childAspectRatio: 0.72),
      itemCount: albums.length,
      itemBuilder: (_, i) => LayoutBuilder(builder: (_, c) => AlbumCard(albums[i], size: c.maxWidth)),
    );
  }
}
