import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/playback.dart';
import '../../state/search.dart';

/// Lyrics of [track]. Synced lyrics follow the playback position (current
/// line highlighted and kept in view); tapping a line seeks to it.
class LyricsView extends ConsumerWidget {
  const LyricsView(this.track, {super.key});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyrics = ref.watch(lyricsProvider(track.id));
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return lyrics.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(child: Text('Paroles indisponibles hors connexion', style: muted)),
      data: (l) {
        if (l == null || l.lines.isEmpty) return Center(child: Text('Pas de paroles pour ce titre', style: muted));
        if (!l.synced) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              l.lines.map((e) => e.text).join('\n'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.6),
              textAlign: TextAlign.center,
            ),
          );
        }
        return _SyncedLyrics(l);
      },
    );
  }
}

class _SyncedLyrics extends ConsumerStatefulWidget {
  const _SyncedLyrics(this.lyrics);
  final Lyrics lyrics;

  @override
  ConsumerState<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends ConsumerState<_SyncedLyrics> {
  late List<GlobalKey> _keys = _makeKeys();
  int _current = -2;

  List<GlobalKey> _makeKeys() => List.generate(widget.lyrics.lines.length, (_) => GlobalKey());

  @override
  void didUpdateWidget(_SyncedLyrics old) {
    super.didUpdateWidget(old);
    if (old.lyrics != widget.lyrics) {
      _keys = _makeKeys();
      _current = -2;
    }
  }

  void _follow(int i) {
    if (i == _current) return;
    _current = i;
    if (i < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[i].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.4,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final lines = widget.lyrics.lines;
    final cur = widget.lyrics.lineAt(pos);
    _follow(cur);
    final scheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.titleLarge!;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 120),
      itemCount: lines.length,
      itemBuilder: (_, i) {
        final active = i == cur;
        return InkWell(
          key: _keys[i],
          borderRadius: BorderRadius.circular(8),
          onTap: () => ref.read(playbackControllerProvider).seek(lines[i].time),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: base.copyWith(
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? scheme.onSurface : scheme.onSurfaceVariant.withValues(alpha: i < cur ? 0.5 : 0.8),
              ),
              textAlign: TextAlign.center,
              child: Text(lines[i].text.isEmpty ? '♪' : lines[i].text),
            ),
          ),
        );
      },
    );
  }
}
