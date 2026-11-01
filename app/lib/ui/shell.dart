import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_info.dart';
import '../data/library_repository.dart';
import '../data/models.dart';
import '../state/library.dart';
import '../state/playback.dart';
import 'dialogs.dart';
import 'nav.dart';
import 'screens/favorites.dart';
import 'screens/home.dart';
import 'screens/library.dart';
import 'screens/playlist.dart';
import 'screens/playlists.dart';
import 'screens/search.dart';
import 'screens/stats.dart';
import 'theme.dart';
import 'widgets/async_view.dart';
import 'widgets/cover.dart';
import 'widgets/mini_player.dart';
import 'widgets/tty.dart';

class _Tab {
  const _Tab(this.label, this.root);
  final String label;
  final Widget root;
}

const _tabs = [
  _Tab('accueil', HomeScreen()),
  _Tab('recherche', SearchScreen()),
  _Tab('biblio', LibraryScreen()),
  _Tab('stats', StatsScreen()),
];

const searchTab = 1;
const biblioTab = 2;

/// Width from which the desktop layout (sidebar + player bar) is used, and
/// from which the "play --now" panel is added on the right.
const desktopWidth = 900.0;
const asideWidth = 1280.0;

/// Lets descendants open a page in a given tab (the sidebar's playlists open
/// in "biblio").
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.open, required this.select, required super.child});
  final void Function(int tab, Widget page) open;
  final void Function(int tab) select;

  static ShellScope? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope old) => false;
}

/// Top-level layout. Desktop: navigation sidebar with the playlists, the
/// current tab, an optional "play --now" panel, and the player bar at the
/// bottom. Mobile: the current tab, the mini player and a text tab bar.
/// Each tab keeps its own navigator (and history).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _keys = List.generate(_tabs.length, (_) => GlobalKey<NavigatorState>());

  void _select(int i) {
    if (i == _index) {
      // Tapping the active tab pops back to its root.
      _keys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _index = i);
    }
  }

  void _open(int tab, Widget page) {
    setState(() => _index = tab);
    _keys[tab].currentState?.push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= desktopWidth;
    final c = Tty.of(context);
    final body = IndexedStack(
      index: _index,
      children: [
        // Inactive tabs keep their state but are offstage (no animations,
        // hidden from screen readers and from hit testing).
        for (var i = 0; i < _tabs.length; i++)
          Offstage(
            offstage: i != _index,
            child: TickerMode(
              enabled: i == _index,
              child: Navigator(
                key: _keys[i],
                onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _tabs[i].root),
              ),
            ),
          ),
      ],
    );
    return ShellScope(
      open: _open,
      select: (i) => setState(() => _index = i),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final nav = _keys[_index].currentState;
          if (nav != null && nav.canPop()) {
            nav.pop();
          } else if (_index != 0) {
            setState(() => _index = 0);
          }
        },
        child: Scaffold(
          body: desktop
              ? Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          SizedBox(
                            width: 240,
                            child: _Sidebar(index: _index, onSelect: _select, onOpen: _open),
                          ),
                          VerticalDivider(width: 1, color: c.border),
                          Expanded(child: body),
                          if (width >= asideWidth) ...[
                            VerticalDivider(width: 1, color: c.border),
                            const SizedBox(width: 300, child: _NowAside()),
                          ],
                        ],
                      ),
                    ),
                    const PlayerBar(),
                  ],
                )
              : SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Expanded(child: body),
                      const MiniPlayer(),
                    ],
                  ),
                ),
          bottomNavigationBar: desktop ? null : _TabBar(index: _index, onSelect: _select),
        ),
      ),
    );
  }
}

/// Mobile tab bar: four words, the active one green with a top rule.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.base,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++)
              Expanded(
                child: Semantics(
                  selected: i == index,
                  button: true,
                  child: InkWell(
                    onTap: () => onSelect(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: i == index ? c.green : Colors.transparent, width: 2)),
                      ),
                      child: Center(
                        heightFactor: 1,
                        child: Text(
                          _tabs[i].label,
                          style: TextStyle(
                            color: i == index ? c.green : c.muted,
                            fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Desktop sidebar: brand, "> section" navigation, playlists, library size.
class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.index, required this.onSelect, required this.onOpen});
  final int index;
  final ValueChanged<int> onSelect;
  final void Function(int tab, Widget page) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Tty.of(context);
    final tree = ref.watch(playlistTreeProvider).value;
    final favCount = ref.watch(favoritesProvider.select((f) => f.value?['tracks']?.length));
    final stats = ref.watch(libraryStatsProvider).value;
    final playingPlaylist = ref.watch(
      playbackStateProvider.select((s) => s.contextKind == 'playlist' && s.playing ? s.contextId : null),
    );
    final actions = ref.read(playlistActionsProvider);

    Widget navItem(int i) {
      final active = i == index;
      return InkWell(
        onTap: () => onSelect(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '${active ? '>' : ' '} ${_tabs[i].label}',
            style: TextStyle(color: active ? c.green : c.muted, fontWeight: active ? FontWeight.w700 : FontWeight.w400),
          ),
        ),
      );
    }

    Widget entry(String text, Color color, VoidCallback onTap, {String? count, bool bold = false}) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text.rich(
          TextSpan(
            children: [
              if (text.startsWith('♥ '))
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: HeartIcon(true, size: 13, color: color),
                  ),
                ),
              TextSpan(text: text.startsWith('♥ ') ? text.substring(2) : text),
              if (count != null)
                TextSpan(
                  text: ' $count',
                  style: TextStyle(color: c.muted, fontWeight: FontWeight.w400),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
        ),
      ),
    );

    return Container(
      color: c.mantle,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appDisplayName,
            style: TextStyle(color: c.mauve, fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < _tabs.length; i++) navItem(i),
          const SizedBox(height: 24),
          TtySection(
            'playlists',
            glyph: '≡',
            color: c.mauve,
            ruled: true,
            trailing: TtyLink(
              '+',
              tooltip: 'Nouvelle playlist',
              onTap: () async {
                final name = await promptText(context, title: 'Nouvelle playlist', action: 'Créer');
                if (name != null && context.mounted) await guard(context, () => actions.createPlaylist(name, null));
              },
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                entry(
                  '♥ titres likés',
                  c.red,
                  () => onOpen(biblioTab, const FavoritesScreen()),
                  count: favCount == null ? null : '$favCount',
                ),
                if (tree != null) ...[
                  for (final f in tree.folders)
                    entry('▸ ${f.name}/', c.muted, () => onOpen(biblioTab, PlaylistsScreen(folderId: f.id))),
                  for (final p in tree.playlists)
                    entry(
                      '${playingPlaylist == p.id ? '▶' : '▸'} ${p.name}',
                      c.accentFor(p.id),
                      () => onOpen(biblioTab, PlaylistScreen(p.id)),
                      bold: playingPlaylist == p.id,
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (stats != null) Comment('${stats.tracks} titres · ${stats.albums} albums'),
          TtyLink('réglages', onTap: () => openSettings(context)),
        ],
      ),
    );
  }
}

/// Right-hand "$ play --now" panel on large screens: what plays and what
/// comes next.
class _NowAside extends ConsumerWidget {
  const _NowAside();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Tty.of(context);
    final st = ref.watch(playbackStateProvider);
    final t = st.current;
    final fav = ref.watch(favoritesProvider.select((f) => t != null && (f.value?['tracks']?.contains(t.id) ?? false)));
    return Container(
      color: c.mantle,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: ListView(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '\$ play --now',
                  style: TextStyle(color: c.mauve, fontWeight: FontWeight.w700),
                ),
              ),
              if (t != null) TtyLink('agrandir', onTap: () => openNowPlaying(context)),
            ],
          ),
          const SizedBox(height: 16),
          if (t == null)
            const Comment('rien en lecture')
          else ...[
            LayoutBuilder(builder: (context, box) => TrackArt(t, size: box.maxWidth)),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        style: TextStyle(color: trackColor(context, t), fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      Comment('${t.artist} · ${t.album}'),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => guard(context, () => ref.read(favoritesProvider.notifier).toggle('tracks', t.id)),
                  child: HeartIcon(fav, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TrackFacts(t),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('≡ à suivre', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  for (var i = st.index + 1; i < st.queue.length && i <= st.index + 5; i++)
                    InkWell(
                      onTap: () => ref.read(playbackControllerProvider).jumpTo(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${(i - st.index + 1).toString().padLeft(2, '0')} ',
                                style: TextStyle(color: c.muted),
                              ),
                              TextSpan(text: st.queue[i].track.title),
                              TextSpan(
                                text: ' · ${st.queue[i].track.artist}',
                                style: TextStyle(color: c.muted),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  if (st.index >= st.queue.length - 1) const Comment('fin de la file'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The big art block of the design: the album cover, or without one a tile
/// with "artist/title.format", "title_" and decorative bars.
class TrackArt extends StatelessWidget {
  const TrackArt(this.track, {super.key, required this.size, this.big = false});
  final Track track;
  final double size;
  final bool big;

  @override
  Widget build(BuildContext context) {
    if (track.coverId != null) {
      return CoverImage(track.coverId, size: size, radius: 8, label: track.artist, seed: track.albumId);
    }
    final c = Tty.of(context);
    final fg = c.accentFor(track.albumId);
    String slug(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.06),
      decoration: BoxDecoration(color: c.tint(fg), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${slug(track.artist)}/${slug(track.title)}.${track.format}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.muted, fontSize: 11),
          ),
          Text(
            '${track.title.toLowerCase()}_',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: big ? 44 : 30, height: 1.1),
          ),
          Text(
            sparkline(track.id, length: 8),
            style: TextStyle(color: fg, fontSize: big ? 28 : 22, letterSpacing: 2),
          ),
        ],
      ),
    );
  }
}

/// "key  value" facts about a track that we do know today (genre, year,
/// file). Tempo, key and energy come with the audio analysis (phase 3).
class TrackFacts extends StatelessWidget {
  const TrackFacts(this.t, {super.key});
  final Track t;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final rows = <(String, String, Color?)>[
      if (t.genre != null) ('genre', t.genre!.toLowerCase(), c.mauve),
      if (t.year != null) ('année', '${t.year}', null),
      (
        'fichier',
        [
          t.format,
          if (t.bitDepth != null && t.sampleRate != null)
            '${t.bitDepth} bits / ${(t.sampleRate! / 1000).toStringAsFixed(1)} kHz'
          else if (t.bitrate != null)
            '${t.bitrate} kb/s',
        ].join(' · '),
        null,
      ),
    ];
    return Column(
      children: [
        for (final (k, v, color) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 90,
                  child: Text(k, style: TextStyle(color: c.muted)),
                ),
                Expanded(
                  child: Text(v, style: TextStyle(color: color)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Library totals for the sidebar footer.
final libraryStatsProvider = FutureProvider<({int tracks, int albums, int artists})>((ref) async {
  ref.watch(homeProvider); // refreshed with the library
  final j = await ref.watch(libraryProvider).me();
  final l = j['library'] as Map<String, dynamic>;
  return (tracks: l['tracks'] as int, albums: l['albums'] as int, artists: l['artists'] as int);
});
