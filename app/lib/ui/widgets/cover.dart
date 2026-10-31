import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Album art from the server, cached on disk by cover id (independent of
/// the server address, so LAN and remote share the cache).
class CoverImage extends ConsumerWidget {
  const CoverImage(this.coverId, {super.key, this.size = 48, this.radius = 6, this.icon = Icons.album});

  final int? coverId;
  final double size;
  final double radius;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHighest,
      child: Icon(icon, size: size * 0.45, color: scheme.onSurfaceVariant),
    );
    Widget child = placeholder;
    if (coverId != null) {
      final api = ref.read(apiProvider);
      final px = size * MediaQuery.devicePixelRatioOf(context);
      final variant = px <= 64 ? 64 : (px <= 300 ? 300 : 800);
      child = CachedNetworkImage(
        imageUrl: api.url('/covers/$coverId?size=$variant'),
        cacheKey: 'cover:$coverId:$variant',
        httpHeaders: api.authHeaders,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: px.round(),
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}

/// 2×2 mosaic of album covers for playlists.
class PlaylistCover extends StatelessWidget {
  const PlaylistCover(this.coverIds, {super.key, this.size = 48});

  final List<int> coverIds;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (coverIds.length < 4) {
      return CoverImage(coverIds.firstOrNull, size: size, icon: Icons.queue_music);
    }
    final half = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: size,
        height: size,
        child: Wrap(children: [for (final id in coverIds.take(4)) CoverImage(id, size: half, radius: 0)]),
      ),
    );
  }
}
