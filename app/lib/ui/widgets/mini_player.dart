import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../playback/audio_engine.dart';
import '../../state/library.dart';
import '../../state/playback.dart';
import '../../state/remote.dart';
import '../format.dart';
import '../nav.dart';
import '../screens/devices.dart';
import '../theme.dart';
import 'cover.dart';
import 'tty.dart';

/// Accent colour of a track (stable per album), used for its title.
Color trackColor(BuildContext context, Track t) => Tty.of(context).accentFor(t.albumId);

/// Mobile player card above the tab bar: play/pause on the left, cover and
/// title (tap opens the full player), like, previous / next, and a thin
/// progress line.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    if (track == null) {
      final elsewhere = ref.watch(remoteDevicesProvider.select((r) => r.activeElsewhere));
      return elsewhere == null ? const SizedBox.shrink() : RemoteMiniBar(elsewhere);
    }
    final playing = ref.watch(playbackStateProvider.select((s) => s.playing));
    final buffering = ref.watch(playbackStateProvider.select((s) => s.buffering));
    final hasNext = ref.watch(playbackStateProvider.select((s) => s.hasNext));
    final fav = ref.watch(favoritesProvider.select((f) => f.value?['tracks']?.contains(track.id) ?? false));
    final c = Tty.of(context);
    final pc = ref.read(playbackControllerProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              buffering && playing
                  ? const SizedBox.square(
                      dimension: 40,
                      child: Center(
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    )
                  : SquareIconButton(
                      icon: playing ? Icons.pause : Icons.play_arrow,
                      tooltip: playing ? 'Pause' : 'Lecture',
                      onPressed: pc.togglePlay,
                    ),
              const SizedBox(width: 4),
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Ouvrir le lecteur',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => openNowPlaying(context),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'now-cover',
                          child: CoverImage(track.coverId, size: 40, label: track.artist, seed: track.albumId),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: trackColor(context, track)),
                              ),
                              Text(
                                '// ${track.artist}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: c.muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SquareIconButton(
                icon: Icons.favorite,
                color: fav ? c.red : c.muted,
                tooltip: fav ? 'Retirer des titres likés' : 'Ajouter aux titres likés',
                onPressed: () => ref.read(favoritesProvider.notifier).toggle('tracks', track.id),
              ),
              SquareIconButton(icon: Icons.skip_previous, tooltip: 'Titre précédent', onPressed: pc.previous),
              SquareIconButton(icon: Icons.skip_next, tooltip: 'Titre suivant', onPressed: hasNext ? pc.next : null),
            ],
          ),
          const SizedBox(height: 8),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: _ThinProgress()),
        ],
      ),
    );
  }
}

class _ThinProgress extends ConsumerWidget {
  const _ThinProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final dur = ref.watch(playbackStateProvider.select((s) => s.duration));
    final v = dur.inMilliseconds == 0 ? 0.0 : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
    return LinearProgressIndicator(value: v, minHeight: 2);
  }
}

/// Desktop player bar at the bottom of the window: track on the left,
/// transport and progress in the middle, lyrics/devices/volume on the right.
class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    final c = Tty.of(context);
    if (track == null) {
      final elsewhere = ref.watch(remoteDevicesProvider.select((r) => r.activeElsewhere));
      return elsewhere == null ? const SizedBox.shrink() : RemoteMiniBar(elsewhere);
    }
    final st = ref.watch(playbackStateProvider);
    final fav = ref.watch(favoritesProvider.select((f) => f.value?['tracks']?.contains(track.id) ?? false));
    final pc = ref.read(playbackControllerProvider);
    Widget transport(IconData icon, String tip, VoidCallback? onTap, {Color? color, double size = 20}) => IconButton(
      icon: Icon(icon, size: size, color: color),
      tooltip: tip,
      onPressed: onTap,
    );

    return Container(
      decoration: BoxDecoration(
        color: c.crust,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: () => openNowPlaying(context),
              child: Row(
                children: [
                  Hero(
                    tag: 'now-cover',
                    child: CoverImage(track.coverId, size: 48, label: track.artist, seed: track.albumId),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: trackColor(context, track)),
                        ),
                        Comment(track.artist, maxLines: 1),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () => ref.read(favoritesProvider.notifier).toggle('tracks', track.id),
                    child: HeartIcon(fav, size: 18),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    transport(
                      Icons.shuffle,
                      'Aléatoire',
                      () => pc.setShuffle(!st.shuffle),
                      color: st.shuffle ? c.green : c.muted,
                      size: 18,
                    ),
                    transport(Icons.skip_previous, 'Précédent', pc.previous),
                    const SizedBox(width: 4),
                    _PlayPill(playing: st.playing, onTap: pc.togglePlay),
                    const SizedBox(width: 4),
                    transport(Icons.skip_next, 'Suivant', st.hasNext ? pc.next : null),
                    transport(
                      st.repeat == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
                      'Répétition',
                      pc.cycleRepeat,
                      color: st.repeat == RepeatMode.off ? c.muted : c.green,
                      size: 18,
                    ),
                  ],
                ),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: const SeekRow()),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 14,
              children: [
                Text(
                  [track.format, if (track.year != null) '${track.year}'].join(' · '),
                  style: TextStyle(color: c.peach),
                ),
                TtyLink('paroles', onTap: () => openNowPlaying(context, lyrics: true)),
                TtyLink('appareils', onTap: () => showDevicesSheet(context)),
                VolumeMeter(value: st.volume, onChanged: pc.setVolume),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The round green play/pause button.
class _PlayPill extends StatelessWidget {
  const _PlayPill({required this.playing, required this.onTap, this.size = 40});
  final bool playing;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    return Tooltip(
      message: playing ? 'Pause' : 'Lecture',
      child: Material(
        color: c.green,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(playing ? Icons.pause : Icons.play_arrow, color: c.base, size: size * 0.5),
          ),
        ),
      ),
    );
  }
}

/// Big variant of the play button for the full player.
class PlayPill extends StatelessWidget {
  const PlayPill({super.key, required this.playing, required this.onTap, this.size = 56});
  final bool playing;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => _PlayPill(playing: playing, onTap: onTap, size: size);
}

/// "1:46 ━━━━━━──── 3:41" with a draggable bar.
class SeekRow extends ConsumerStatefulWidget {
  const SeekRow({super.key});

  @override
  ConsumerState<SeekRow> createState() => _SeekRowState();
}

class _SeekRowState extends ConsumerState<SeekRow> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final dur = ref.watch(playbackStateProvider.select((s) => s.duration));
    final max = dur.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final value = (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, max);
    return Row(
      children: [
        Text(formatDuration(Duration(milliseconds: value.round())), style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5)),
            child: Slider(
              value: value,
              max: max,
              onChanged: (v) => setState(() => _drag = v),
              onChangeEnd: (v) {
                ref.read(playbackControllerProvider).seek(Duration(milliseconds: v.round()));
                setState(() => _drag = null);
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(formatDuration(dur), style: TextStyle(fontSize: 12, color: c.muted)),
      ],
    );
  }
}

/// "vol [██████░░]": tap or drag along it to set the volume.
class VolumeMeter extends StatelessWidget {
  const VolumeMeter({super.key, required this.value, required this.onChanged, this.cells = 8});
  final double value;
  final ValueChanged<double> onChanged;
  final int cells;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('vol ', style: TextStyle(color: c.muted)),
        LayoutBuilder(
          builder: (context, _) {
            void set(Offset local, Size size) => onChanged((local.dx / size.width).clamp(0.0, 1.0));
            return Tooltip(
              message: 'Volume ${(value * 100).round()} %',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => set(d.localPosition, (context.findRenderObject()! as RenderBox).size),
                onHorizontalDragUpdate: (d) => set(d.localPosition, (context.findRenderObject()! as RenderBox).size),
                child: TtyMeter(value, cells: cells),
              ),
            );
          },
        ),
      ],
    );
  }
}
