import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../data/library_repository.dart';
import '../../data/models.dart';
import '../../state/playback.dart';
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
  String? _error;
  bool _loading = false;

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () => _run(q));
  }

  Future<void> _run(String q) async {
    _cancel?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _result = const SearchResult();
        _error = null;
      });
      return;
    }
    final token = _cancel = CancelToken();
    setState(() => _loading = true);
    try {
      final r = await ref.read(libraryProvider).search(q, cancel: token);
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
        bottom: _loading
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : r.isEmpty
              ? Center(child: Text(_ctrl.text.isEmpty ? 'Recherchez dans votre bibliothèque' : 'Aucun résultat'))
              : ListView(children: [
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
                      TrackTile(r.tracks[i], onTap: () => c.playTracks(r.tracks, index: i, contextKind: 'search')),
                  ],
                  const SizedBox(height: 16),
                ]),
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
