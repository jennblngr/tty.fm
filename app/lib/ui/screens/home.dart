import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_info.dart';
import '../../state/library.dart';
import '../../state/notifications.dart';
import '../daily_message.dart';
import '../icons.dart';
import '../nav.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/async_view.dart';
import '../widgets/cover.dart';
import '../widgets/tty.dart';
import 'favorites.dart';

/// "$ accueil": recently played, recently added. Daily mixes, new releases
/// and artist radios arrive with recommendations (phase 3).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final favCount = ref.watch(favoritesProvider.select((f) => f.value?['tracks']?.length ?? 0));
    final wide = MediaQuery.sizeOf(context).width >= desktopWidth;
    final message = ref.watch(dailyMessageProvider);
    final unread = ref.watch(unreadNotificationsProvider);
    final c = Tty.of(context);
    final shell = ShellScope.of(context);

    return AsyncView(
      home,
      onRetry: () => ref.invalidate(homeProvider),
      builder: (h) {
        final header = TtyPrompt(
          'accueil',
          brand: wide ? null : appDisplayName,
          commentSpans: message?.spans(c) ?? [TextSpan(text: '${greeting()}.')],
          trailing: wide
              ? InkWell(
                  onTap: () => shell?.select(searchTab),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 260),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(6)),
                    child: Text('> grep titre, artiste, bpm:…', style: TextStyle(color: c.muted)),
                  ),
                )
              : Transform.translate(
                  // Box 40, icon 20: shifted by the 10 px of padding so the
                  // gear lines up with the 16 px page margin, as on 01.
                  offset: const Offset(10, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SquareIconButton(
                        svg: bellSvg,
                        size: 20,
                        color: c.muted,
                        badge: unread > 0 ? c.peach : null,
                        tooltip: unread > 0
                            ? 'Notifications, $unread non lue${unread > 1 ? 's' : ''}'
                            : 'Notifications',
                        onPressed: () => openNotifications(context),
                      ),
                      SquareIconButton(
                        svg: gearSvg,
                        size: 20,
                        color: c.muted,
                        tooltip: 'Réglages',
                        onPressed: () => openSettings(context),
                      ),
                    ],
                  ),
                ),
        );

        // One tile size for the chips and the recently added rows: 48 px on
        // mobile, 52 px on desktop, as on the mockups.
        final tile = wide ? 52.0 : 48.0;
        final played = <Widget>[
          _Chip(
            label: 'titres likés',
            // The heart at the size of the mockup's "♥" (13 px text).
            tile: Container(
              width: tile,
              height: tile,
              color: c.tint(c.red),
              alignment: Alignment.center,
              child: HeartIcon(true, size: 12, color: c.red),
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FavoritesScreen())),
            trailing: favCount > 0 ? '$favCount' : null,
          ),
          for (final r in h.recentlyPlayed.take(wide ? 7 : 3))
            if (r.album case final a?)
              _Chip(
                label: '${a.artist} — ${a.title}'.toLowerCase(),
                tile: CoverImage(a.coverId, size: tile, radius: 0, label: a.artist, seed: a.id),
                onTap: () => openAlbum(context, a.id),
              )
            else if (r.artist case final a?)
              _Chip(
                label: a.name.toLowerCase(),
                tile: CoverImage(a.coverId, size: tile, radius: 0, label: a.name, seed: a.id),
                onTap: () => openArtist(context, a.id),
              )
            else if (r.playlist case final p?)
              _Chip(
                label: p.name.toLowerCase(),
                tile: PlaylistCover(p.coverIds, size: tile, radius: 0, label: p.name, seed: p.id),
                onTap: () => openPlaylist(context, p.id),
              ),
        ];

        final added = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Lists: ruled header on desktop only. On mobile, 4 px + the 8 px
            // of the row: 12 px under the title, as above the grid.
            TtySection(
              'ajouts récents',
              glyph: '+',
              color: c.peach,
              ruled: wide,
              trailing: TtyLink('biblio', onTap: () => shell?.select(biblioTab)),
            ),
            if (!wide) const SizedBox(height: 4),
            // Desktop: two columns of at least 300 px, 32 px apart, as on
            // the mockup (grid gap 0 32 px).
            TtyGrid(
              minWidth: 300,
              spacing: 32,
              runSpacing: 0,
              maxColumns: wide ? 2 : 1,
              children: [
                for (final r in h.recentlyAdded.take(2))
                  if (r.album case final a)
                    TtyRow(
                      leading: CoverImage(a.coverId, size: tile, label: a.artist, seed: a.id),
                      title: a.title.toLowerCase(),
                      titleColor: c.accentFor(a.id),
                      // "album · ajouté hier" for a whole album, "3 titres ·
                      // ajoutés il y a 2 j" for a few tracks of it.
                      subtitle: [
                        a.artist.toLowerCase(),
                        if (r.wholeAlbum) 'album' else '${r.tracks} titre${r.tracks > 1 ? 's' : ''}',
                        if (r.addedAt != null)
                          '${r.wholeAlbum || r.tracks == 1 ? 'ajouté' : 'ajoutés'} ${relativeDay(r.addedAt!)}',
                      ].join(' · '),
                      aside: a.year == null ? null : Text('${a.year}', style: TextStyle(color: c.muted)),
                      onTap: () => openAlbum(context, a.id),
                    ),
              ],
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
                  TtySection('écouté récemment', svg: recentSvg, color: c.green),
                  const SizedBox(height: 12),
                  TtyGrid(minWidth: wide ? 220 : 150, maxColumns: wide ? 99 : 2, children: played),
                ],
              ),
            if (h.recentlyAdded.isNotEmpty) added,
          ],
        );
      },
    );
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
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
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
