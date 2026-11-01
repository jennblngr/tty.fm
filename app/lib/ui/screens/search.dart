import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../data/library_repository.dart';
import '../../data/models.dart';
import '../../state/playback.dart';
import '../../state/search.dart';
import '../nav.dart';
import '../widgets/album_card.dart';
import '../widgets/cover.dart';
import '../widgets/track_tile.dart';
import '../widgets/tty.dart';
import '../shell.dart';
import '../theme.dart';

/// Search as you type: each keystroke cancels the previous request.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  CancelToken? _cancel;
  SearchResult _result = const SearchResult();
  SearchFilter _filter = const SearchFilter();
  String? _error;
  bool _loading = false;

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () => _run(q));
  }

  Future<void> _run(String q) async {
    _cancel?.cancel();
    if (q.trim().isEmpty && !_filter.isActive) {
      setState(() {
        _result = const SearchResult();
        _error = null;
      });
      return;
    }
    final token = _cancel = CancelToken();
    setState(() => _loading = true);
    try {
      final r = await ref
          .read(libraryProvider)
          .search(q, filter: _filter, limit: q.trim().isEmpty ? 300 : 30, cancel: token);
      if (!token.isCancelled && mounted) {
        setState(() {
          _result = r;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) return;
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _loading = false;
        });
      }
    }
  }

  void _setFilter(SearchFilter f) {
    setState(() => _filter = f);
    _run(_ctrl.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cancel?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final pc = ref.read(playbackControllerProvider);
    final c = Tty.of(context);
    final wide = MediaQuery.sizeOf(context).width >= desktopWidth;
    final idle = _ctrl.text.trim().isEmpty && !_filter.isActive;

    final input = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Text('>', style: TextStyle(color: c.green)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _ctrl,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'titre, artiste, album…',
                filled: false,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_ctrl.text.isNotEmpty)
            IconButton(
              tooltip: 'Effacer',
              icon: Icon(Icons.clear, size: 18, color: c.muted),
              onPressed: () {
                _ctrl.clear();
                _run('');
              },
            ),
        ],
      ),
    );

    final Widget results;
    if (_error != null) {
      results = Comment(_error!);
    } else if (idle) {
      results = _Browse(onGenre: (g) => _setFilter(_filter.copyWith(genre: () => g)));
    } else if (r.isEmpty) {
      results = Comment(_loading ? 'recherche…' : 'aucun résultat');
    } else {
      final best = r.artists.isNotEmpty
          ? _BestResult.artist(r.artists.first)
          : r.albums.isNotEmpty
          ? _BestResult.album(r.albums.first)
          : null;
      final tracks = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TtySection('titres', glyph: '♪', color: c.mauve, ruled: true),
          for (var i = 0; i < r.tracks.length; i++)
            TrackTile(
              r.tracks[i],
              onTap: () => pc.playTracks(r.tracks, index: i, contextKind: 'search'),
            ),
        ],
      );
      results = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (wide && best != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 320, child: best),
                const SizedBox(width: 32),
                if (r.tracks.isNotEmpty) Expanded(child: tracks),
              ],
            )
          else ...[
            ?best,
            if (r.tracks.isNotEmpty) ...[const SizedBox(height: 24), tracks],
          ],
          if (r.albums.isNotEmpty) ...[
            const SizedBox(height: 24),
            TtySection('albums', glyph: '◉', color: c.peach),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [for (final a in r.albums) AlbumCard(a, size: 150)],
              ),
            ),
          ],
          if (r.artists.length > 1) ...[
            const SizedBox(height: 24),
            TtySection('artistes', glyph: '●', color: c.teal),
            for (final a in r.artists)
              TtyRow(
                leading: CoverImage(a.coverId, size: 40, radius: 20, label: a.name, seed: a.id),
                title: a.name.toLowerCase(),
                titleColor: c.accentFor(a.id),
                subtitle: '${a.albumCount} album${a.albumCount > 1 ? 's' : ''}',
                onTap: () => openArtist(context, a.id),
              ),
          ],
        ],
      );
    }

    return TtyPage(
      gap: 16,
      children: [
        TtyPrompt(wide ? 'recherche' : 'grep'),
        input,
        Row(
          children: [
            Text('filtres :', style: TextStyle(color: c.muted)),
            const SizedBox(width: 8),
            Expanded(
              child: _FilterBar(filter: _filter, onChanged: _setFilter),
            ),
          ],
        ),
        SizedBox(height: 2, child: _loading ? const LinearProgressIndicator(minHeight: 2) : null),
        results,
      ],
    );
  }
}

/// "★ meilleur résultat": the top artist (or album) as a card.
class _BestResult extends StatelessWidget {
  const _BestResult._({
    required this.title,
    required this.subtitle,
    required this.tile,
    required this.onTap,
    required this.seed,
  });

  factory _BestResult.artist(Artist a) => _BestResult._(
    title: a.name,
    subtitle: 'artiste · ${a.albumCount} album${a.albumCount > 1 ? 's' : ''}',
    tile: CoverImage(a.coverId, size: 88, radius: 44, label: a.name, seed: a.id),
    onTap: (context) => openArtist(context, a.id),
    seed: a.id,
  );

  factory _BestResult.album(Album a) => _BestResult._(
    title: a.title,
    subtitle: 'album · ${a.artist.toLowerCase()}${a.year == null ? '' : ' · ${a.year}'}',
    tile: CoverImage(a.coverId, size: 88, radius: 6, label: a.artist, seed: a.id),
    onTap: (context) => openAlbum(context, a.id),
    seed: a.id,
  );

  final String title;
  final String subtitle;
  final Widget tile;
  final void Function(BuildContext) onTap;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TtySection('meilleur résultat', glyph: '★', color: c.green),
        const SizedBox(height: 10),
        Material(
          color: c.surface,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onTap(context),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tile,
                  const SizedBox(height: 10),
                  Text(
                    title.toLowerCase(),
                    style: TextStyle(color: c.accentFor(seed), fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  Comment(subtitle),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "▦ parcourir": the library's genres as tiles (tap filters by genre).
class _Browse extends ConsumerWidget {
  const _Browse({required this.onGenre});
  final ValueChanged<String> onGenre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Tty.of(context);
    final facets = ref.watch(searchFacetsProvider).value;
    if (facets == null || facets.genres.isEmpty) return const Comment('cherche un titre, un artiste ou un album');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TtySection('parcourir', glyph: '▦', color: c.mauve),
        const SizedBox(height: 10),
        TtyGrid(
          minWidth: 150,
          spacing: 12,
          children: [
            for (final (i, g) in facets.genres.take(16).indexed)
              () {
                final color = c.accents[(i + 4) % c.accents.length];
                return Material(
                  color: c.tint(color),
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => onGenre(g.name),
                    child: Container(
                      height: 88,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            g.name.toLowerCase(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: color, fontWeight: FontWeight.w700),
                          ),
                          Text.rich(
                            TextSpan(
                              children: [
                                miniGraphSpan(sparkline(g.name.hashCode, length: 4), color: color),
                                TextSpan(text: ' · ${g.count} titres'),
                              ],
                            ),
                            style: TextStyle(color: c.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }(),
          ],
        ),
      ],
    );
  }
}

/// Genre / period / format filter chips.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filter, required this.onChanged});
  final SearchFilter filter;
  final ValueChanged<SearchFilter> onChanged;

  static String _decade(int d) => 'années ${d >= 2000 ? d : d % 100}';

  String _periodLabel(SearchFilter f) {
    final (lo, hi) = (f.yearMin, f.yearMax);
    if (lo == null && hi == null) return 'période';
    if (lo != null && hi == lo + 9 && lo % 10 == 0) return _decade(lo);
    return '${lo ?? '…'} – ${hi ?? '…'}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facets = ref.watch(searchFacetsProvider).value ?? const SearchFacets();
    final decades = <int>[
      if (facets.yearMin != null && facets.yearMax != null)
        for (var d = facets.yearMin! ~/ 10 * 10; d <= facets.yearMax!; d += 10) d,
    ];

    final c = Tty.of(context);
    // Menu values are callbacks: a null value would count as "cancelled".
    Widget chip<T>(String label, bool selected, List<(String, T)> options, void Function(T?) pick) => Padding(
      padding: const EdgeInsets.only(right: 12),
      child: PopupMenuButton<VoidCallback>(
        tooltip: '',
        onSelected: (f) => f(),
        itemBuilder: (_) => [
          if (selected) PopupMenuItem(value: () => pick(null), child: const Text('tous')),
          for (final (text, value) in options) PopupMenuItem(value: () => pick(value), child: Text(text)),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            selected ? label : '$label ▾',
            style: TextStyle(
              color: selected ? c.peach : c.muted,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip<String>(filter.genre == null ? 'genre' : 'genre:${filter.genre!.toLowerCase()}', filter.genre != null, [
            for (final g in facets.genres) ('${g.name.toLowerCase()} (${g.count})', g.name),
          ], (g) => onChanged(filter.copyWith(genre: () => g))),
          chip<int>(_periodLabel(filter), filter.yearMin != null || filter.yearMax != null, [
            for (final d in decades.reversed) (_decade(d), d),
          ], (d) => onChanged(filter.copyWith(yearMin: () => d, yearMax: () => d == null ? null : d + 9))),
          chip<String>(filter.format == null ? 'format' : 'format:${filter.format}', filter.format != null, [
            for (final f in facets.formats) ('${f.name} (${f.count})', f.name),
          ], (f) => onChanged(filter.copyWith(format: () => f))),
          if (filter.isActive) Center(child: TtyLink('effacer', onTap: () => onChanged(const SearchFilter()))),
        ],
      ),
    );
  }
}
