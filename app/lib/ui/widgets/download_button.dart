import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../offline/downloads.dart';
import '../dialogs.dart';

/// Download / downloading / downloaded toggle for an album, a playlist or
/// the favourites. [tracks] is null while the list is still loading.
class DownloadButton extends ConsumerWidget {
  const DownloadButton({
    super.key,
    required this.kind,
    required this.id,
    required this.title,
    required this.tracks,
    this.subtitle = '',
    this.coverIds = const [],
  });

  final String kind;
  final int id;
  final String title;
  final String subtitle;
  final List<int> coverIds;
  final List<Track>? tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(downloadsProvider.select((s) => s.status(kind, id)));
    final (done, total) = ref.watch(downloadsProvider.select((s) => s.progress(kind, id)));
    final dm = ref.read(downloadsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    Future<void> askRemove() async {
      if (await confirm(context, 'Supprimer le téléchargement ?', '« $title » ne sera plus disponible hors ligne.')) {
        dm.remove(kind, id);
      }
    }

    switch (status) {
      case CollectionStatus.none:
        return IconButton(
          icon: const Icon(Icons.download_for_offline_outlined),
          tooltip: 'Télécharger',
          onPressed: tracks == null || tracks!.isEmpty
              ? null
              : () => dm.add(
                  OfflineCollection(kind: kind, id: id, title: title, subtitle: subtitle, coverIds: coverIds),
                  tracks!,
                ),
        );
      case CollectionStatus.downloading:
        return IconButton(
          tooltip: 'Téléchargement : $done / $total',
          onPressed: askRemove,
          icon: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, value: total == 0 ? null : done / total),
          ),
        );
      case CollectionStatus.done:
        return IconButton(
          icon: Icon(Icons.download_done, color: scheme.primary),
          tooltip: 'Disponible hors ligne',
          onPressed: askRemove,
        );
    }
  }
}
