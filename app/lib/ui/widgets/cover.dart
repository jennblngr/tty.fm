import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../theme.dart';
import 'tty.dart';

/// Album art from the server, cached on disk by cover id (independent of
/// the server address, so LAN and remote share the cache). Without art, a
/// coloured tile with the initials of [label] (or [glyph]) stands in.
class CoverImage extends ConsumerWidget {
  const CoverImage(
    this.coverId, {
    super.key,
    this.size = 48,
    this.radius = 6,
    this.label = '',
    this.seed,
    this.glyph,
    this.icon = Icons.album,
  });

  final int? coverId;
  final double size;
  final double radius;
  final String label;
  final int? seed;
  final String? glyph;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Tty.of(context);
    final Widget placeholder = label.isNotEmpty || glyph != null
        ? InitialsTile(label, seed: seed ?? label.hashCode, size: size, radius: 0, glyph: glyph)
        : Container(
            width: size,
            height: size,
            color: c.surface,
            child: Icon(icon, size: size * 0.45, color: c.muted),
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
  const PlaylistCover(this.coverIds, {super.key, this.size = 48, this.label = '', this.seed});

  final List<int> coverIds;
  final double size;
  final String label;
  final int? seed;

  @override
  Widget build(BuildContext context) {
    if (coverIds.length < 4) {
      return CoverImage(coverIds.firstOrNull, size: size, label: label, seed: seed, glyph: label.isEmpty ? '≡' : null);
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
