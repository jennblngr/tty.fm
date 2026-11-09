import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_info.dart';
import '../../data/library_repository.dart';
import '../../data/models.dart';
import '../../state/library.dart';
import '../../state/notifications.dart';
import '../../state/playback.dart';
import '../daily_message.dart';
import '../format.dart';
import '../icons.dart';
import '../nav.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/async_view.dart';
import '../widgets/cover.dart';
import '../widgets/tty.dart';
import 'favorites.dart';

/// "$ accueil": recently played, recently added, daily mixes, new
/// releases, discoveries and artist radios.
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
            if (h.mixes.isNotEmpty) _Mixes(h.mixes),
            if (h.newReleases.isNotEmpty) _NewReleases(h.newReleases.take(4).toList()),
            if (h.discoveries.isNotEmpty) _Discoveries(h.discoveries.take(5).toList()),
            if (h.artistRadios.isNotEmpty) _ArtistRadios(h.artistRadios),
          ],
        );
      },
    );
  }
}

/// "✦ tes mix du jour" (02 Main, D1): one tile per mix, side by side and
/// scrolling sideways; a tap plays the mix.
class _Mixes extends ConsumerWidget {
  const _Mixes(this.mixes);
  final List<DailyMix> mixes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Tty.of(context);
    final colors = [c.blue, c.mauve, c.peach, c.green, c.pink, c.yellow];
    Future<void> play(DailyMix m) => guard(context, () async {
      final tracks = await ref.read(libraryProvider).mixTracks(m.position);
      await ref
          .read(playbackControllerProvider)
          .playTracks(tracks, shuffle: false, contextKind: 'mix', contextId: m.position);
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TtySection('tes mix du jour', glyph: '✦', color: c.mauve, comment: 'générés selon tes écoutes'),
        const SizedBox(height: 12),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: mixes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final m = mixes[i];
              final color = colors[i % colors.length];
              return SizedBox(
                width: 140,
                child: InkWell(
                  onTap: () => play(m),
                  borderRadius: BorderRadius.circular(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        button: true,
                        label: 'Lire ${m.name}, ${m.trackCount} titres',
                        child: Container(
                          width: 140,
                          height: 140,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: c.tint(color), borderRadius: BorderRadius.circular(6)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                m.name,
                                style: TextStyle(color: color, fontWeight: FontWeight.w700),
                              ),
                              MiniGraph(sparkline(m.position * 7919, length: 6), color: color, fontSize: 18),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '// ${m.caption}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// "● nouvelles sorties" (02 Main, D1): recent and upcoming releases of
/// the library's artists, "[✓]" when the library has them (a tap opens the
/// album); otherwise a tap opens the artist.
class _NewReleases extends StatelessWidget {
  const _NewReleases(this.releases);
  final List<NewRelease> releases;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final wide = MediaQuery.sizeOf(context).width >= desktopWidth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TtySection('nouvelles sorties', glyph: '●', color: c.teal, ruled: wide),
        const SizedBox(height: 4),
        for (final r in releases)
          TtyRow(
            leading: CoverImage(null, size: 44, label: r.artist, seed: r.artistId),
            title: r.title.toLowerCase(),
            titleColor: c.teal,
            subtitle: newReleaseSubtitle(r),
            trailing: r.albumId == null ? null : Text('[✓]', style: TextStyle(color: c.green)),
            onTap: () => r.albumId != null ? openAlbum(context, r.albumId!) : openArtist(context, r.artistId),
          ),
      ],
    );
  }
}

/// "◇ à découvrir": artists close to the liked ones that the library lacks
/// (ListenBrainz). Not in the library, so nothing to play: a list to look
/// up elsewhere.
class _Discoveries extends StatelessWidget {
  const _Discoveries(this.items);
  final List<Discovery> items;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final wide = MediaQuery.sizeOf(context).width >= desktopWidth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TtySection('à découvrir', glyph: '◇', color: c.yellow, ruled: wide, comment: 'hors de ta biblio'),
        const SizedBox(height: 4),
        for (final (i, d) in items.indexed)
          TtyRow(
            leading: InitialsTile(d.name, size: 44, color: c.accents[i % c.accents.length]),
            title: d.name.toLowerCase(),
            titleColor: c.accents[i % c.accents.length],
            subtitle: d.caption,
          ),
      ],
    );
  }
}

/// "◉ radios d'artistes" (02 Main, D1): round 104 px covers scrolling
/// sideways, the name under each; a tap starts the artist's radio.
class _ArtistRadios extends ConsumerWidget {
  const _ArtistRadios(this.artists);
  final List<ArtistRadio> artists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Tty.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TtySection("radios d'artistes", glyph: '◉', color: c.yellow),
        const SizedBox(height: 12),
        SizedBox(
          height: 136,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: artists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final a = artists[i];
              final color = c.accentFor(a.id);
              return SizedBox(
                width: 104,
                child: Semantics(
                  button: true,
                  label: 'Lancer la radio de ${a.name}',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => guard(context, () => ref.read(playbackControllerProvider).startRadio(a.seed)),
                    borderRadius: BorderRadius.circular(52),
                    child: Column(
                      children: [
                        CoverImage(a.coverId, size: 104, radius: 52, label: a.name, seed: a.id),
                        const SizedBox(height: 8),
                        Text(
                          a.name.toLowerCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: color, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// "charlotte cardin · album · à venir le 29 janv. 2027", "sia · single ·
/// sorti le 20 août" (the year only when it is not the current one).
String newReleaseSubtitle(NewRelease r, {DateTime? now}) {
  final d = r.date;
  final year = (now ?? DateTime.now()).year;
  String day(DateTime d) {
    final s = formatDate(d);
    return d.year == year ? s.substring(0, s.length - 5) : s;
  }

  final String? when;
  if (d == null) {
    when = null;
  } else if (r.released.length == 7) {
    // Only the month is known: "sorti en août", "à venir en janv. 2027".
    final month = day(d).split(' ').skip(1).join(' ');
    when = '${r.upcoming ? 'à venir' : 'sorti'} en $month';
  } else {
    when = '${r.upcoming ? 'à venir le' : 'sorti le'} ${day(d)}';
  }
  return [r.artist.toLowerCase(), if (r.kind == 'ep') 'EP' else r.kind, ?when].join(' · ');
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
