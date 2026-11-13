import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/library.dart';
import '../widgets/async_view.dart';
import '../widgets/release_row.dart';
import '../widgets/tty.dart';

/// "[tout]" of "● nouvelles sorties": every release of the library's
/// artists from the last 90 days, and the upcoming ones.
class ReleasesScreen extends ConsumerWidget {
  const ReleasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final releases = ref.watch(releasesProvider);
    return Scaffold(
      appBar: AppBar(),
      body: AsyncView(
        releases,
        onRetry: () => ref.invalidate(releasesProvider),
        builder: (items) => TtyPage(
          onRefresh: () => ref.refresh(releasesProvider.future),
          children: [
            TtyPrompt(
              'ls ~/sorties',
              comment: items.isEmpty
                  ? 'aucune sortie de tes artistes ces 90 derniers jours.'
                  : '${items.length} sortie${items.length > 1 ? 's' : ''} · 90 derniers jours et à venir',
            ),
            Column(children: [for (final r in items) ReleaseRow(r)]),
          ],
        ),
      ),
    );
  }
}
