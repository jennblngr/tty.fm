import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/library.dart';
import '../../state/playback.dart';
import '../dialogs.dart';
import '../format.dart';
import '../nav.dart';
import 'async_view.dart';
import 'cover.dart';
import 'tty.dart';
import '../theme.dart';

/// A track row: number or cover, coloured title, "// artist · album",
/// duration and the "···" menu. [onTap] usually plays the list it belongs
/// to from here.
class TrackTile extends ConsumerWidget {
  const TrackTile(
    this.track, {
    super.key,
    this.onTap,
    this.showCover = true,
    this.leadingNumber,
    this.extraMenu = const [],
    this.trailing,
  });

  final Track track;
  final VoidCallback? onTap;
  final bool showCover;
  final int? leadingNumber;
  final List<PopupMenuEntry<VoidCallback>> extraMenu;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCurrent = ref.watch(currentTrackProvider.select((t) => t?.id == track.id));
    final c = Tty.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            if (showCover)
              CoverImage(track.coverId, size: 40, label: track.artist, seed: track.albumId)
            else
              SizedBox(
                width: 28,
                child: Text(
                  isCurrent ? '▶' : (leadingNumber ?? track.trackNo ?? '').toString().padLeft(2, '0'),
                  style: TextStyle(color: isCurrent ? c.green : c.muted),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent ? c.green : c.text,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  Comment(showCover ? '${track.artist} · ${track.album}' : track.artist, maxLines: 1),
                ],
              ),
            ),
            ?trailing,
            const SizedBox(width: 8),
            Text(formatDuration(track.duration), style: TextStyle(color: c.muted, fontSize: 12)),
            TrackMenuButton(track, extra: extraMenu),
          ],
        ),
      ),
    );
  }
}

/// "⋮" menu with the common track actions.
class TrackMenuButton extends ConsumerWidget {
  const TrackMenuButton(this.track, {super.key, this.extra = const []});

  final Track track;
  final List<PopupMenuEntry<VoidCallback>> extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fav = ref.watch(favoritesProvider.select((f) => f.value?['tracks']?.contains(track.id) ?? false));
    final c = ref.read(playbackControllerProvider);
    PopupMenuItem<VoidCallback> item(IconData icon, String label, VoidCallback action) => PopupMenuItem(
      value: action,
      child: ListTile(leading: Icon(icon), title: Text(label), dense: true),
    );
    return PopupMenuButton<VoidCallback>(
      icon: Text('···', style: TextStyle(color: Tty.of(context).muted)),
      tooltip: 'Plus',
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        item(Icons.playlist_play, 'Lire ensuite', () {
          c.playNext([track]);
          toast(context, 'Lira ensuite');
        }),
        item(Icons.queue_music, 'Ajouter à la file', () {
          c.addToQueue([track]);
          toast(context, 'Ajouté à la file');
        }),
        item(Icons.playlist_add, 'Ajouter à une playlist…', () => addToPlaylist(context, ref, [track])),
        item(
          fav ? Icons.favorite : Icons.favorite_border,
          fav ? 'Retirer des favoris' : 'Ajouter aux favoris',
          () => guard(context, () => ref.read(favoritesProvider.notifier).toggle('tracks', track.id)),
        ),
        const PopupMenuDivider(),
        item(Icons.album_outlined, 'Aller à l\'album', () => openAlbum(context, track.albumId)),
        item(Icons.person_outline, 'Aller à l\'artiste', () => openArtist(context, track.artistId)),
        ...extra,
      ],
    );
  }
}
