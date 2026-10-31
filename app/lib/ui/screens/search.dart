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
    final c = ref.read(playbackControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: false,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Titre, artiste, album…',
            border: InputBorder.none,
            suffixIcon: _ctrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _ctrl.clear();
                      _run('');
                    },
                  ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Column(
            children: [
              _FilterBar(filter: _filter, onChanged: _setFilter),
              SizedBox(height: 2, child: _loading ? const LinearProgressIndicator(minHeight: 2) : null),
            ],
          ),
        ),
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : r.isEmpty
          ? Center(child: Text(_ctrl.text.isEmpty ? 'Recherchez dans votre bibliothèque' : 'Aucun résultat'))
          : ListView(
              children: [
                if (r.artists.isNotEmpty) ...[
                  const _Section('Artistes'),
                  for (final a in r.artists)
                    ListTile(
                      leading: CoverImage(a.coverId, size: 40, radius: 20, icon: Icons.person),
                      title: Text(a.name),
                      onTap: () => openArtist(context, a.id),
                    ),
                ],
                if (r.albums.isNotEmpty) ...[
                  const _Section('Albums'),
                  SizedBox(
                    height: 200,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [for (final a in r.albums) AlbumCard(a, size: 150)],
                    ),
                  ),
                ],
                if (r.tracks.isNotEmpty) ...[
                  const _Section('Titres'),
                  for (var i = 0; i < r.tracks.length; i++)
                    TrackTile(
                      r.tracks[i],
                      onTap: () => c.playTracks(r.tracks, index: i, contextKind: 'search'),
                    ),
                ],
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// Genre / period / format filter chips.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filter, required this.onChanged});
  final SearchFilter filter;
  final ValueChanged<SearchFilter> onChanged;

  static String _decade(int d) => 'Années ${d >= 2000 ? d : d % 100}';

  String _periodLabel(SearchFilter f) {
    final (lo, hi) = (f.yearMin, f.yearMax);
    if (lo == null && hi == null) return 'Période';
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

    // Menu values are callbacks: a null value would count as "cancelled".
    Widget chip<T>(String label, bool selected, List<(String, T)> options, void Function(T?) pick) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<VoidCallback>(
        tooltip: '',
        onSelected: (f) => f(),
        itemBuilder: (_) => [
          if (selected) PopupMenuItem(value: () => pick(null), child: const Text('Tous')),
          for (final (text, value) in options) PopupMenuItem(value: () => pick(value), child: Text(text)),
        ],
        child: Chip(
          label: Text(label),
          avatar: selected ? const Icon(Icons.check, size: 16) : const Icon(Icons.arrow_drop_down, size: 18),
          side: selected ? BorderSide(color: Theme.of(context).colorScheme.primary) : null,
        ),
      ),
    );

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          chip<String>(filter.genre ?? 'Genre', filter.genre != null, [
            for (final g in facets.genres) ('${g.name} (${g.count})', g.name),
          ], (g) => onChanged(filter.copyWith(genre: () => g))),
          chip<int>(_periodLabel(filter), filter.yearMin != null || filter.yearMax != null, [
            for (final d in decades.reversed) (_periodLabel(SearchFilter(yearMin: d, yearMax: d + 9)), d),
          ], (d) => onChanged(filter.copyWith(yearMin: () => d, yearMax: () => d == null ? null : d + 9))),
          chip<String>(filter.format?.toUpperCase() ?? 'Format', filter.format != null, [
            for (final f in facets.formats) ('${f.name.toUpperCase()} (${f.count})', f.name),
          ], (f) => onChanged(filter.copyWith(format: () => f))),
          if (filter.isActive)
            TextButton.icon(
              icon: const Icon(Icons.clear, size: 18),
              label: const Text('Effacer'),
              onPressed: () => onChanged(const SearchFilter()),
            ),
        ],
      ),
    );
  }
}
