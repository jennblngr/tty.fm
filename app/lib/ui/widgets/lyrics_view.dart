import 'package:material_ui/material_ui.dart';
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
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 15, height: 1.7),
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
  final _scroll = ScrollController();
  int _current = -2;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

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
      // Only the lyrics list scrolls (Scrollable.ensureVisible would also
      // scroll the page around it).
      final ro = _keys[i].currentContext?.findRenderObject();
      if (ro != null && _scroll.hasClients) {
        _scroll.position.ensureVisible(
          ro,
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
    final base = Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 16);
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 80),
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
                fontSize: active ? 19 : 16,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: active ? scheme.onSurface : scheme.onSurfaceVariant.withValues(alpha: i < cur ? 0.6 : 1),
              ),
              child: Text('${active ? '> ' : ''}${lines[i].text.isEmpty ? '♪' : lines[i].text}'),
            ),
          ),
        );
      },
    );
  }
}
