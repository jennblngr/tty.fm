import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/library.dart';
import '../../state/playback.dart';
import '../../state/search.dart';
import '../../data/library_repository.dart';
import '../dialogs.dart';
import '../format.dart';
import '../nav.dart';
import 'async_view.dart';
import 'cover.dart';
import 'tty.dart';
import '../theme.dart';

/// A track row: a 24 px square with the number (or the green play icon for
/// the current track, so nothing shifts), the cover, the title, "// artist ·
/// album", duration and the "···" menu. Without a number and with a cover,
/// the square is left out and the current track shows in green. [onTap] usually plays the list it belongs
/// to from here. A hidden track is greyed out and cannot be played from
/// here; its menu can show it again.
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
    final hidden = ref.watch(hiddenTracksProvider.select((h) => h.value?.contains(track.id) ?? false));
    final c = Tty.of(context);
    final number = leadingNumber ?? (showCover ? null : track.trackNo ?? 0);
    // Greyed out, the menu excepted: it stays readable to show the track again.
    Widget dim(Widget w) => hidden ? Opacity(opacity: 0.4, child: w) : w;
    return InkWell(
      onTap: hidden ? null : onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            if (number != null)
              dim(
                SizedBox.square(
                  dimension: 24,
                  child: Center(
                    child: isCurrent
                        ? Icon(Icons.play_arrow, size: 18, color: c.green, semanticLabel: 'en cours')
                        : Text(number.toString().padLeft(2, '0'), style: TextStyle(color: c.muted)),
                  ),
                ),
              ),
            if (number != null && showCover) const SizedBox(width: 12),
            if (showCover) dim(CoverImage(track.coverId, size: 40, label: track.artist, seed: track.albumId)),
            const SizedBox(width: 12),
            Expanded(
              child: dim(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent ? c.green : c.text,
                        decoration: hidden ? TextDecoration.lineThrough : null,
                        decorationColor: c.muted,
                      ),
                    ),
                    Comment(
                      [
                        if (hidden) 'archivé',
                        showCover ? '${track.artist} · ${track.album}' : track.artist,
                      ].join(' · '),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ),
            ?trailing,
            if (track.bpm != null) ...[
              const SizedBox(width: 8),
              dim(Text('${track.bpm!.round()}', style: TextStyle(color: c.peach, fontSize: 12))),
            ],
            const SizedBox(width: 8),
            dim(Text(formatDuration(track.duration), style: TextStyle(color: c.muted, fontSize: 12))),
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
    final hidden = ref.watch(hiddenTracksProvider.select((h) => h.value?.contains(track.id) ?? false));
    final c = ref.read(playbackControllerProvider);
    void setHidden(bool on) => guard(context, () => ref.read(hiddenTracksProvider.notifier).set(track.id, on));
    PopupMenuItem<VoidCallback> item(IconData icon, String label, VoidCallback action) => PopupMenuItem(
      value: action,
      child: ListTile(leading: Icon(icon), title: Text(label), dense: true),
    );
    return PopupMenuButton<VoidCallback>(
      icon: Text('···', style: TextStyle(color: Tty.of(context).muted)),
      tooltip: 'Plus',
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        if (!hidden) ...[
          item(Icons.playlist_play, 'Lire ensuite', () {
            c.playNext([track]);
            toast(context, 'Lira ensuite');
          }),
          item(Icons.queue_music, 'Ajouter à la file', () {
            c.addToQueue([track]);
            toast(context, 'Ajouté à la file');
          }),
        ],
        item(Icons.playlist_add, 'Ajouter à une playlist…', () => addToPlaylist(context, ref, [track])),
        item(
          fav ? Icons.favorite : Icons.favorite_border,
          fav ? 'Retirer des favoris' : 'Ajouter aux favoris',
          () => guard(context, () => ref.read(favoritesProvider.notifier).toggle('tracks', track.id)),
        ),
        const PopupMenuDivider(),
        item(Icons.album_outlined, 'Aller à l\'album', () => openAlbum(context, track.albumId)),
        item(Icons.person_outline, 'Aller à l\'artiste', () => openArtist(context, track.artistId)),
        const PopupMenuDivider(),
        item(
          Icons.graphic_eq,
          'Relancer l\'analyse',
          () => guard(context, () async {
            await ref.read(libraryProvider).resetAnalysis(track.id);
            ref.invalidate(analysisProvider(track.id));
          }, success: 'Analyse relancée'),
        ),
        // Groupe « bibliothèque », avant les retraits propres à l'écran (Menus-Contextuels, règles 2 et 3).
        const PopupMenuDivider(),
        hidden
            ? item(Icons.unarchive_outlined, 'Désarchiver', () => setHidden(false))
            : item(Icons.archive_outlined, 'Archiver', () {
                setHidden(true);
                toastUndo(context, '« ${track.title.toLowerCase()} » archivé.', () => setHidden(false));
              }),
        ...extra,
      ],
    );
  }
}
