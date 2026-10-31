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

/// A track row. [onTap] usually plays the list it belongs to from here.
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
    final scheme = Theme.of(context).colorScheme;
    final style = isCurrent ? TextStyle(color: scheme.primary, fontWeight: FontWeight.w600) : null;
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: showCover
          ? CoverImage(track.coverId, size: 40)
          : SizedBox(
              width: 28,
              child: Center(
                child: isCurrent
                    ? Icon(Icons.graphic_eq, color: scheme.primary, size: 18)
                    : Text('${leadingNumber ?? track.trackNo ?? ''}',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
      subtitle: Text(showCover ? '${track.artist} · ${track.album}' : track.artist,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        ?trailing,
        Text(formatDuration(track.duration), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        TrackMenuButton(track, extra: extraMenu),
      ]),
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
    PopupMenuItem<VoidCallback> item(IconData icon, String label, VoidCallback action) =>
        PopupMenuItem(value: action, child: ListTile(leading: Icon(icon), title: Text(label), dense: true));
    return PopupMenuButton<VoidCallback>(
      icon: const Icon(Icons.more_vert, size: 20),
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
        item(fav ? Icons.favorite : Icons.favorite_border, fav ? 'Retirer des favoris' : 'Ajouter aux favoris',
            () => guard(context, () => ref.read(favoritesProvider.notifier).toggle('tracks', track.id))),
        const PopupMenuDivider(),
        item(Icons.album_outlined, 'Aller à l\'album', () => openAlbum(context, track.albumId)),
        item(Icons.person_outline, 'Aller à l\'artiste', () => openArtist(context, track.artistId)),
        ...extra,
      ],
    );
  }
}
