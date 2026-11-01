import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/library.dart';
import '../../state/playback.dart';
import '../nav.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/async_view.dart';
import '../widgets/cover.dart';
import '../widgets/tty.dart';
import '../widgets/track_tile.dart';
import 'favorites.dart';

/// "$ accueil": recently played, recently added, last tracks. Daily mixes
/// and new releases arrive with recommendations (phase 3).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final favCount = ref.watch(favoritesProvider.select((f) => f.value?['tracks']?.length ?? 0));
    final wide = MediaQuery.sizeOf(context).width >= desktopWidth;
    final c = Tty.of(context);
    final shell = ShellScope.of(context);

    return AsyncView(
      home,
      onRetry: () => ref.invalidate(homeProvider),
      builder: (h) {
        final header = TtyPrompt(
          'accueil',
          comment: h.recentlyAdded.isEmpty
              ? '${greeting()}. bibliothèque vide : ajoute de la musique dans le dossier du NAS.'
              : '${greeting()}. ${_addedRecently(h.recentlyAdded)}',
          trailing: wide
              ? InkWell(
                  onTap: () => shell?.select(searchTab),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 280,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(6)),
                    child: Text('> grep titre, artiste, album…', style: TextStyle(color: c.muted)),
                  ),
                )
              : IconButton(
                  icon: Icon(Icons.settings_outlined, color: c.muted),
                  tooltip: 'Réglages',
                  onPressed: () => openSettings(context),
                ),
        );

        final played = <Widget>[
          _Chip(
            label: 'titres likés',
            tile: InitialsTile('', size: 48, radius: 0, color: c.red, glyph: '♥'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FavoritesScreen())),
            trailing: favCount > 0 ? '$favCount' : null,
          ),
          for (final a in h.recentlyPlayed.take(wide ? 7 : 5))
            _Chip(
              label: '${a.artist} — ${a.title}'.toLowerCase(),
              tile: CoverImage(a.coverId, size: 48, radius: 0, label: a.artist, seed: a.id),
              onTap: () => openAlbum(context, a.id),
            ),
        ];

        final added = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TtySection(
              'ajouts récents',
              glyph: '+',
              color: c.peach,
              ruled: true,
              trailing: TtyLink('biblio', onTap: () => shell?.select(biblioTab)),
            ),
            for (final a in h.recentlyAdded.take(wide ? 6 : 4))
              TtyRow(
                leading: CoverImage(a.coverId, size: 44, label: a.artist, seed: a.id),
                title: a.title.toLowerCase(),
                titleColor: c.accentFor(a.id),
                subtitle: [
                  a.artist.toLowerCase(),
                  'album',
                  if (a.createdAt != null) 'ajouté ${relativeDay(a.createdAt!)}',
                ].join(' · '),
                trailing: a.year == null ? null : Text('${a.year}', style: TextStyle(color: c.muted)),
                onTap: () => openAlbum(context, a.id),
              ),
          ],
        );

        final tracks = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TtySection('derniers titres', glyph: '♪', color: c.teal, ruled: true),
            for (var i = 0; i < h.recentTracks.length && i < (wide ? 6 : 5); i++)
              TrackTile(
                h.recentTracks[i],
                onTap: () =>
                    ref.read(playbackControllerProvider).playTracks(h.recentTracks, index: i, contextKind: 'history'),
              ),
          ],
        );

        return TtyPage(
          onRefresh: () => ref.refresh(homeProvider.future),
          children: [
            header,
            if (played.length > 1 || favCount > 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TtySection('écouté récemment', glyph: '↺', color: c.green),
                  const SizedBox(height: 10),
                  TtyGrid(minWidth: wide ? 220 : 150, maxColumns: wide ? 99 : 2, children: played),
                ],
              ),
            if (h.recentlyAdded.isNotEmpty || h.recentTracks.isNotEmpty)
              wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: added),
                        const SizedBox(width: 32),
                        Expanded(child: h.recentTracks.isEmpty ? const SizedBox() : tracks),
                      ],
                    )
                  : Column(
                      children: [
                        if (h.recentlyAdded.isNotEmpty) added,
                        if (h.recentTracks.isNotEmpty) ...[const SizedBox(height: 28), tracks],
                      ],
                    ),
          ],
        );
      },
    );
  }

  static String _addedRecently(List<Album> albums) {
    final week = DateTime.now().subtract(const Duration(days: 7));
    final n = albums.where((a) => a.createdAt != null && a.createdAt!.isAfter(week)).length;
    return n == 0 ? 'rien de neuf cette semaine.' : '$n ajout${n > 1 ? 's' : ''} cette semaine.';
  }
}

/// Recently played shortcut: tile + label on a surface strip.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.tile, required this.onTap, this.trailing});
  final String label;
  final Widget tile;
  final VoidCallback onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            tile,
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
            ),
            if (trailing != null) ...[
              Text(trailing!, style: TextStyle(color: c.muted, fontSize: 12)),
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }
}
