import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_info.dart';
import '../../offline/downloads.dart';
import '../../data/models.dart';
import '../../state/library.dart';
import '../../state/playback.dart';
import '../dialogs.dart';
import '../format.dart';
import '../nav.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/album_card.dart';
import '../widgets/async_view.dart';
import '../widgets/cover.dart';
import '../widgets/track_tile.dart';
import '../widgets/tty.dart';
import 'favorites.dart';
import 'offline.dart';

enum _View { playlists, albums, artistes, titres }

/// "$ biblio": playlists (with the pinned likes and offline items), albums,
/// artists and tracks, switched with "[bracket]" links. Whole lists are
/// loaded once and cached, so scrolling is instant.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  var _view = _View.playlists;
  var _albumSort = 'added';

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= desktopWidth;
    final pad = wide ? const EdgeInsets.fromLTRB(32, 24, 32, 0) : const EdgeInsets.fromLTRB(16, 16, 16, 0);
    final c = Tty.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: pad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Header(),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final v in _View.values)
                        TtyLink(v.name, active: v == _view, onTap: () => setState(() => _view = v)),
                      if (_view == _View.albums) ...[
                        Text('|', style: TextStyle(color: c.border)),
                        for (final (k, l) in const [('added', 'récents'), ('name', 'a-z'), ('year', 'année')])
                          TtyLink(l, active: _albumSort == k, onTap: () => setState(() => _albumSort = k)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: switch (_view) {
                _View.playlists => const _Playlists(),
                _View.albums => _Albums(_albumSort),
                _View.artistes => const _Artists(),
                _View.titres => const _Tracks(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(libraryStatsProvider).value;
    final playlists = ref.watch(playlistTreeProvider).value?.allPlaylists.length;
    final offline = ref.watch(downloadsProvider.select((s) => s.tracks.length));
    final wide = MediaQuery.sizeOf(context).width >= desktopWidth;
    return TtyPrompt(
      'ls ~/biblio',
      brand: wide ? null : appDisplayName,
      comment: [
        if (playlists != null) '$playlists playlists',
        if (stats != null) '${stats.artists} artistes',
        if (stats != null) '${stats.tracks} titres',
        '$offline hors-ligne',
      ].join('. '),
    );
  }
}

EdgeInsets _listPadding(BuildContext context) => MediaQuery.sizeOf(context).width >= desktopWidth
    ? const EdgeInsets.fromLTRB(24, 8, 24, 24)
    : const EdgeInsets.fromLTRB(8, 8, 8, 24);

/// Pinned items (likes, offline) then the root of the playlist tree.
class _Playlists extends ConsumerWidget {
  const _Playlists();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Tty.of(context);
    final tree = ref.watch(playlistTreeProvider);
    final favCount = ref.watch(favoritesProvider.select((f) => f.value?['tracks']?.length ?? 0));
    final offline = ref.watch(downloadsProvider);
    final actions = ref.read(playlistActionsProvider);
    final pad = _listPadding(context);
    return AsyncView(
      tree,
      onRetry: () => ref.invalidate(playlistTreeProvider),
      builder: (t) => RefreshIndicator(
        onRefresh: () => ref.refresh(playlistTreeProvider.future),
        child: ListView(
          padding: pad,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TtySection('épinglés', glyph: '♥', color: c.red, ruled: true),
            ),
            _Item(
              tile: InitialsTile('', size: 44, color: c.red, glyph: '♥'),
              title: 'titres likés',
              titleColor: c.red,
              subtitle: '$favCount titres',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FavoritesScreen())),
            ),
            _Item(
              tile: InitialsTile('', size: 44, color: c.green, glyph: '↓'),
              title: 'hors-ligne',
              titleColor: c.green,
              subtitle: '${offline.tracks.length} titres · ${formatBytes(offline.totalBytes)}',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(appBar: AppBar(), body: const OfflineList()),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TtySection(
                'playlists',
                glyph: '≡',
                color: c.mauve,
                ruled: true,
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    TtyLink(
                      '+ playlist',
                      onTap: () async {
                        final name = await promptText(context, title: 'Nouvelle playlist', action: 'Créer');
                        if (name != null && context.mounted) {
                          await guard(context, () => actions.createPlaylist(name, null));
                        }
                      },
                    ),
                    TtyLink(
                      '+ dossier',
                      onTap: () async {
                        final name = await promptText(context, title: 'Nouveau dossier', action: 'Créer');
                        if (name != null && context.mounted) {
                          await guard(context, () => actions.createFolder(name, null));
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (t.folders.isEmpty && t.playlists.isEmpty)
              const Padding(padding: EdgeInsets.all(8), child: Comment('aucune playlist pour l\'instant')),
            for (final f in t.folders)
              _Item(
                tile: InitialsTile('', size: 44, color: c.muted, glyph: '▸'),
                title: '${f.name}/',
                subtitle: '${f.folders.length} dossiers · ${f.playlists.length} playlists',
                onTap: () => openFolder(context, f.id),
              ),
            for (final p in t.playlists)
              _Item(
                tile: PlaylistCover(p.coverIds, size: 44, label: p.name, seed: p.id),
                title: p.name,
                titleColor: c.accentFor(p.id),
                subtitle: formatCountDuration(p.trackCount, p.durationMs).toLowerCase(),
                trailing: offline.status('playlist', p.id) == CollectionStatus.done
                    ? Text('↓', style: TextStyle(color: c.green))
                    : null,
                onTap: () => openPlaylist(context, p.id),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: TtyLink('réorganiser', onTap: () => openFolderRoot(context)),
            ),
            const SizedBox(height: 12),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: FollowedArtists()),
          ],
        ),
      ),
    );
  }
}

/// "● artistes suivis [23] ▾" (03, D3): the followed artists as chips, a
/// red "•" by those with a new release; folded, the first ones and "+N".
class FollowedArtists extends ConsumerStatefulWidget {
  const FollowedArtists({super.key});

  @override
  ConsumerState<FollowedArtists> createState() => _FollowedArtistsState();
}

class _FollowedArtistsState extends ConsumerState<FollowedArtists> {
  var _open = false;

  /// Chips shown while folded (03 shows four, D3 five).
  static const folded = 4;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final follows = ref.watch(followsProvider).value ?? const <FollowedArtist>[];
    if (follows.isEmpty) return const SizedBox.shrink();
    final shown = _open ? follows : follows.take(folded).toList();
    final hidden = follows.length - shown.length;
    Widget chip(String label, Color color, VoidCallback onTap, {bool dot = false}) => Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: label),
                if (dot)
                  TextSpan(
                    text: ' •',
                    style: TextStyle(color: c.red),
                  ),
              ],
            ),
            style: TextStyle(color: color),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TtySection(
          'artistes suivis',
          glyph: '●',
          color: c.teal,
          ruled: true,
          trailing: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Text('[${follows.length}] ${_open ? '▴' : '▾'}', style: TextStyle(color: c.muted)),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in shown)
              chip(a.name.toLowerCase(), c.accentFor(a.id), () => openArtist(context, a.id), dot: a.newRelease != null),
            if (hidden > 0) chip('+$hidden', c.muted, () => setState(() => _open = true)),
          ],
        ),
        if (follows.any((a) => a.newRelease != null)) ...[
          const SizedBox(height: 8),
          const Comment('• = nouvelle sortie'),
        ],
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.tile, required this.title, this.subtitle, this.titleColor, this.trailing, this.onTap});
  final Widget tile;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: TtyRow(
      leading: tile,
      title: title,
      titleColor: titleColor,
      subtitle: subtitle,
      trailing: trailing,
      onTap: onTap,
    ),
  );
}

class _Albums extends ConsumerWidget {
  const _Albums(this.sort);
  final String sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider(sort));
    final archived = ref.watch(archivedAlbumsProvider);
    return AsyncView(
      albums,
      onRetry: () => ref.invalidate(albumsProvider(sort)),
      builder: (list) => RefreshIndicator(
        onRefresh: () => ref.refresh(albumsProvider(sort).future),
        child: Padding(
          padding: _listPadding(context).copyWith(top: 0, bottom: 0),
          child: AlbumGrid(withoutArchived(list, archived)),
        ),
      ),
    );
  }
}

class _Artists extends ConsumerWidget {
  const _Artists();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);
    final c = Tty.of(context);
    return AsyncView(
      artists,
      onRetry: () => ref.invalidate(artistsProvider),
      builder: (list) => RefreshIndicator(
        onRefresh: () => ref.refresh(artistsProvider.future),
        child: ListView.builder(
          padding: _listPadding(context),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final a = list[i];
            return _Item(
              tile: CoverImage(a.coverId, size: 44, radius: 22, label: a.name, seed: a.id),
              title: a.name.toLowerCase(),
              titleColor: c.accentFor(a.id),
              subtitle: '${a.albumCount} album${a.albumCount > 1 ? 's' : ''}',
              onTap: () => openArtist(context, a.id),
            );
          },
        ),
      ),
    );
  }
}

class _Tracks extends ConsumerWidget {
  const _Tracks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(tracksProvider);
    final c = Tty.of(context);
    return AsyncView(
      tracks,
      onRetry: () => ref.invalidate(tracksProvider),
      builder: (list) {
        final pc = ref.read(playbackControllerProvider);
        return RefreshIndicator(
          onRefresh: () => ref.refresh(tracksProvider.future),
          child: ListView.builder(
            padding: _listPadding(context),
            itemCount: list.length + 1,
            itemBuilder: (_, i) => i == 0
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Row(
                      children: [
                        Expanded(child: Comment('${list.length} titres')),
                        TtyLink(
                          'tout en aléatoire',
                          color: c.green,
                          onTap: () => pc.playTracks(list, shuffle: true, contextKind: 'library'),
                        ),
                      ],
                    ),
                  )
                : TrackTile(
                    list[i - 1],
                    onTap: () => pc.playTracks(list, index: i - 1, contextKind: 'library'),
                  ),
          ),
        );
      },
    );
  }
}
