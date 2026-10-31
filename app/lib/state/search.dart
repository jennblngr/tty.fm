import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/library_repository.dart';
import '../data/models.dart';

/// Values offered by the search filters (genres, formats, year range).
final searchFacetsProvider = StreamProvider<SearchFacets>((ref) => ref.watch(libraryProvider).searchFacets());

/// Lyrics of a track (null: none).
final lyricsProvider = FutureProvider.autoDispose.family<Lyrics?, int>(
  (ref, id) => ref.watch(libraryProvider).lyrics(id),
);
