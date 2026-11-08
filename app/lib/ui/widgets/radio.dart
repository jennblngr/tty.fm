import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../data/models.dart';
import '../../playback/audio_engine.dart';
import '../../playback/playback_controller.dart';
import '../../state/playback.dart';
import '../dialogs.dart';
import 'async_view.dart';
import 'tty.dart';

/// "lancer la radio" from a track: the rest of the queue is replaced by
/// tracks that sound alike (Menus-Contextuels). Asks first when the queue
/// still holds tracks the user added.
Future<void> launchRadio(BuildContext context, WidgetRef ref, Track track) async {
  final c = ref.read(playbackControllerProvider);
  if (c.state.hasUserUpcoming &&
      !await confirm(
        context,
        'Lancer la radio ?',
        'Les titres que tu as ajoutés à la file seront remplacés.',
        action: 'Lancer',
      )) {
    return;
  }
  if (!context.mounted) return;
  await guard(
    context,
    () => c.startRadio(RadioSeed.track(track), from: track),
    success: 'Radio « ${track.title.toLowerCase()} »',
  );
}

/// The line after the last queued track: "ensuite : radio « … »" while a
/// radio fills the queue or when "lecture auto" will start one (Lecteur,
/// D3); null when the queue just stops.
String? queueTail(PlaybackState st, {required bool autoplay}) {
  if (st.queue.isEmpty) return null;
  final radio = st.radio;
  if (radio != null) return 'ensuite : radio « ${radio.name.toLowerCase()} »';
  if (autoplay && st.repeat == RepeatMode.off) {
    return 'ensuite : radio « ${st.queue.last.track.title.toLowerCase()} »';
  }
  return null;
}

/// " · ajouté par toi" / " · radio" after a queued track, '' otherwise.
String queueSourceSuffix(QueueItem item) => switch (item.source) {
  QueueSource.user => ' · ajouté par toi',
  QueueSource.radio => ' · radio',
  QueueSource.context => '',
};

/// [queueTail] as a comment line, with the "lecture auto" setting.
class QueueTail extends ConsumerWidget {
  const QueueTail({super.key, this.orEnd = false});

  /// Shows "fin de la file" when nothing follows.
  final bool orEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(playbackStateProvider);
    final tail = queueTail(st, autoplay: ref.watch(settingsProvider.select((s) => s.autoplay)));
    if (tail == null && !orEnd) return const SizedBox.shrink();
    return Comment(tail ?? 'fin de la file');
  }
}
