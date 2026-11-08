import 'dart:io';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network.dart';
import '../../core/settings.dart';
import '../../data/models.dart';
import '../../offline/downloads.dart';
import '../../playback/audio_engine.dart';
import '../../state/library.dart';
import '../../state/playback.dart';
import '../../state/search.dart';
import '../dialogs.dart';
import '../format.dart';
import '../nav.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/async_view.dart';
import '../widgets/cover.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/mini_player.dart';
import '../widgets/player_menu.dart';
import '../widgets/radio.dart';
import '../widgets/tty.dart';
import 'devices.dart';

/// "$ lecteur": art, track, lyrics, file facts, queue and sound settings.
/// Desktop: two columns plus the queue on the right and the player bar.
/// Phone: one scrolling column with the transport under the art.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key, this.showLyrics = false});

  /// Opened from a "[paroles]" link: lyrics come first on phones.
  final bool showLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    final wide = MediaQuery.sizeOf(context).width >= desktopWidth;
    final c = Tty.of(context);
    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Comment('rien en lecture')),
      );
    }
    final header = Row(
      // [···] sits on the line of "$ lecteur" (02, D2).
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (!wide) TtyLink('fermer', onTap: () => Navigator.pop(context)),
        if (!wide) const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '\$ ',
                      style: TextStyle(color: c.green),
                    ),
                    TextSpan(text: wide ? 'lecteur' : 'play --now'),
                  ],
                ),
                style: const TextStyle(fontSize: 15),
              ),
              const _ContextLine(),
            ],
          ),
        ),
        PlayerMenuButton(track),
        if (wide) ...[const SizedBox(width: 16), TtyLink('réduire', onTap: () => Navigator.pop(context))],
      ],
    );

    if (wide) {
      return PlayerMenuShortcuts(
        track: track,
        child: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
                        children: [
                          header,
                          const SizedBox(height: 24),
                          TtyGrid(
                            minWidth: 340,
                            spacing: 32,
                            children: [
                              _TrackBlock(track, wide: true),
                              Column(
                                children: [
                                  _LyricsPanel(track, height: 340),
                                  const SizedBox(height: 24),
                                  _FileFacts(track),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    VerticalDivider(width: 1, color: c.border),
                    Container(
                      width: 320,
                      color: c.mantle,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                        children: const [_QueueSection(compact: false), SizedBox(height: 24), _SoundSection()],
                      ),
                    ),
                  ],
                ),
              ),
              const PlayerBar(),
            ],
          ),
        ),
      );
    }

    final lyrics = _LyricsPanel(track, height: 260);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            header,
            const SizedBox(height: 16),
            if (showLyrics) ...[lyrics, const SizedBox(height: 20)],
            _TrackBlock(track, wide: false),
            const SizedBox(height: 8),
            const SeekRow(),
            const _Transport(),
            const SizedBox(height: 4),
            const _QualityLine(),
            const SizedBox(height: 12),
            _ActionButtons(track),
            if (!showLyrics) ...[const SizedBox(height: 24), lyrics],
            const SizedBox(height: 24),
            _FileFacts(track),
            const SizedBox(height: 24),
            const _SoundSection(),
            const SizedBox(height: 24),
            const _QueueSection(compact: true),
          ],
        ),
      ),
    );
  }
}

/// "// depuis la playlist « x »".
class _ContextLine extends ConsumerWidget {
  const _ContextLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(playbackStateProvider);
    final tree = ref.watch(playlistTreeProvider).value;
    final t = st.current;
    final text = switch (st.contextKind) {
      'album' => "depuis l'album « ${t?.album.toLowerCase()} »",
      'playlist' =>
        'depuis la playlist « ${tree?.allPlaylists.where((p) => p.id == st.contextId).firstOrNull?.name ?? '…'} »',
      'favorites' => 'depuis tes titres likés',
      'search' => 'depuis la recherche',
      'artist' => "depuis l'artiste « ${t?.artist.toLowerCase()} »",
      'history' => 'depuis ton historique',
      'library' => 'depuis la bibliothèque',
      _ => null,
    };
    return text == null ? const SizedBox() : Comment(text);
  }
}

/// Art, title, "// artist · album · year", genre chip and like.
class _TrackBlock extends ConsumerWidget {
  const _TrackBlock(this.track, {required this.wide});
  final Track track;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Tty.of(context);
    final fav = ref.watch(favoritesProvider.select((f) => f.value?['tracks']?.contains(track.id) ?? false));
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.maxWidth.clamp(120.0, wide ? 420.0 : 520.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'now-cover',
              child: TrackArt(track, size: size, big: wide),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: size,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title.toLowerCase(),
                          style: TextStyle(
                            color: trackColor(context, track),
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            openArtist(context, track.artistId);
                          },
                          child: Comment(
                            [
                              track.artist.toLowerCase(),
                              'album « ${track.album.toLowerCase()} »',
                              if (track.year != null) '${track.year}',
                            ].join(' · '),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (track.genre != null)
                              Text('[${track.genre!.toLowerCase()}]', style: TextStyle(color: c.mauve, fontSize: 12)),
                            InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                openAlbum(context, track.albumId);
                              },
                              child: Text('[album]', style: TextStyle(color: c.muted, fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: fav ? 'Retirer des titres likés' : 'Ajouter aux titres likés',
                    onPressed: () =>
                        guard(context, () => ref.read(favoritesProvider.notifier).toggle('tracks', track.id)),
                    icon: HeartIcon(fav, size: 24),
                  ),
                ],
              ),
            ),
            if (wide) ...[const SizedBox(height: 12), SizedBox(width: size, child: _ActionButtons(track))],
          ],
        );
      },
    );
  }
}

/// "⌁ cet appareil" (devices) and "+ playlist" buttons.
class _ActionButtons extends ConsumerWidget {
  const _ActionButtons(this.track);
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Tty.of(context);
    final phone = Platform.isAndroid || Platform.isIOS;
    Widget button(String label, Color color, VoidCallback onTap) => Expanded(
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
          ),
        ),
      ),
    );
    return Row(
      children: [
        button(phone ? '⌁ ce tél.' : '⌁ cet ordi', c.green, () => showDevicesSheet(context)),
        const SizedBox(width: 8),
        button('+ playlist', c.text, () => addToPlaylist(context, ref, [track])),
      ],
    );
  }
}

/// Phone transport: shuffle, previous, play, next, repeat.
class _Transport extends ConsumerWidget {
  const _Transport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Tty.of(context);
    final st = ref.watch(playbackStateProvider);
    final pc = ref.read(playbackControllerProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: 'Aléatoire',
          icon: Icon(Icons.shuffle, color: st.shuffle ? c.green : c.muted),
          onPressed: () => pc.setShuffle(!st.shuffle),
        ),
        IconButton(tooltip: 'Précédent', iconSize: 30, icon: const Icon(Icons.skip_previous), onPressed: pc.previous),
        PlayPill(playing: st.playing, onTap: pc.togglePlay, size: 60),
        IconButton(
          tooltip: 'Suivant',
          iconSize: 30,
          icon: const Icon(Icons.skip_next),
          onPressed: st.hasNext ? pc.next : null,
        ),
        IconButton(
          tooltip: 'Répétition',
          icon: Icon(
            st.repeat == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
            color: st.repeat == RepeatMode.off ? c.muted : c.green,
          ),
          onPressed: pc.cycleRepeat,
        ),
      ],
    );
  }
}

/// "// opus 192 kb/s · à distance" or "// fichier local".
class _QualityLine extends ConsumerWidget {
  const _QualityLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(currentTrackProvider);
    final local = t != null && ref.watch(downloadsProvider.select((s) => s.tracks.containsKey(t.id)));
    final q = ref.watch(streamQualityProvider);
    final link = ref.watch(routeProvider.select((r) => r.link));
    final where = switch (link) {
      LinkType.local => 'réseau local',
      LinkType.remoteWifi => 'à distance',
      LinkType.cellular => 'réseau mobile',
    };
    return Center(child: Comment(local ? 'fichier téléchargé' : '${q.label.toLowerCase()} · $where'));
  }
}

class _LyricsPanel extends StatelessWidget {
  const _LyricsPanel(this.track, {required this.height});
  final Track track;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    return TtyPanel(
      color: c.tint(c.mauve),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\$ paroles',
            style: TextStyle(color: c.mauve, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: height, child: LyricsView(track)),
        ],
      ),
    );
  }
}

/// "\$ analyse --piste": tags, file and audio analysis, then a track that
/// chains well after this one. Before the analysis: "\$ stat --piste".
class _FileFacts extends ConsumerWidget {
  const _FileFacts(this.track);
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Tty.of(context);
    final result = ref.watch(analysisProvider(track.id)).value;
    final a = result?.analysis;
    final analysed = a != null && a.error == null;
    final next = result?.compatible.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TtySection(
          analysed ? 'analyse --piste' : 'stat --piste',
          glyph: '∿',
          color: c.peach,
          comment: switch (a) {
            null => 'analyse audio en attente',
            TrackAnalysis(error: != null) => 'analyse impossible pour ce fichier',
            TrackAnalysis(stale: true) => 'calculé à partir du fichier audio · fichier modifié, à refaire',
            _ => 'calculé à partir du fichier audio',
          },
        ),
        const SizedBox(height: 6),
        TrackFacts(track),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              SizedBox(
                width: 90,
                child: Text('durée', style: TextStyle(color: c.muted)),
              ),
              Text(formatDuration(track.duration)),
            ],
          ),
        ),
        if (next != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Comment.rich([
              const TextSpan(text: 'enchaînement compatible : '),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: InkWell(
                  onTap: () {
                    ref.read(playbackControllerProvider).playNext([next]);
                    toast(context, 'Lira ensuite');
                  },
                  child: Text(next.title.toLowerCase(), style: TextStyle(color: c.text)),
                ),
              ),
              TextSpan(text: ' (${[if (next.bpm != null) '${next.bpm!.round()} bpm', ?next.camelot].join(', ')})'),
            ]),
          ),
      ],
    );
  }
}

/// "⚙ son": stream quality for the current network, sleep timer.
class _SoundSection extends ConsumerWidget {
  const _SoundSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Tty.of(context);
    final s = ref.watch(settingsProvider);
    final link = ref.watch(routeProvider.select((r) => r.link));
    final current = ref.watch(streamQualityProvider);
    final sleep = ref.watch(sleepTimerProvider);
    final timer = ref.read(sleepTimerProvider.notifier);

    Settings apply(StreamQuality q) => switch (link) {
      LinkType.local => s.copyWith(qualityLocal: q),
      LinkType.remoteWifi => s.copyWith(qualityRemoteWifi: q),
      LinkType.cellular => s.copyWith(qualityCellular: q),
    };
    String short(StreamQuality q) => q == StreamQuality.original ? 'orig' : '${q.bitrate}';
    final left = sleep?.endsAt?.difference(DateTime.now());

    Widget line(String label, List<Widget> options) => Row(
      children: [
        Expanded(child: Text(label)),
        Wrap(children: options),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '⚙ ',
                style: TextStyle(color: c.green),
              ),
              const TextSpan(text: 'son'),
            ],
          ),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        line('qualité', [
          for (final q in StreamQuality.values)
            TtyLink(
              short(q),
              active: q == current,
              tooltip: q.label,
              onTap: () => ref.read(settingsProvider.notifier).update(apply(q)),
            ),
        ]),
        line('minuteur', [
          TtyLink('off', active: sleep == null, onTap: timer.off),
          for (final m in const [15, 30, 60])
            TtyLink(
              '$m',
              active: sleep?.endsAt != null && left != null && (left.inMinutes - m).abs() < 1,
              onTap: () => timer.after(Duration(minutes: m)),
            ),
          TtyLink('fin', active: sleep?.endOfTrack ?? false, onTap: timer.atEndOfTrack),
        ]),
        if (sleep?.endsAt != null) Comment('pause à ${TimeOfDay.fromDateTime(sleep!.endsAt!).format(context)}'),
        if (sleep?.endOfTrack ?? false) const Comment('pause à la fin du titre'),
      ],
    );
  }
}

/// "≡ file d'attente": what comes next. Compact (phone): the next tracks,
/// tap to jump, with a link to the full reorderable queue.
class _QueueSection extends ConsumerWidget {
  const _QueueSection({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Tty.of(context);
    final st = ref.watch(playbackStateProvider);
    final remainingMs = [for (var i = st.index + 1; i < st.queue.length; i++) st.queue[i].track.durationMs]
        .fold<int>(0, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: "≡ file d'attente",
                      style: TextStyle(color: c.mauve, fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: ' [${st.queue.length}] · ${formatDuration(Duration(milliseconds: remainingMs))}',
                      style: TextStyle(color: c.muted),
                    ),
                  ],
                ),
              ),
            ),
            TtyLink(
              'réorganiser',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text("file d'attente")),
                    body: const QueueView(),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (compact) ...[
          for (var i = st.index; i < st.queue.length && i < st.index + 12; i++) _QueueRow(i),
          if (st.queue.length <= st.index + 12) const Padding(padding: EdgeInsets.only(top: 6), child: QueueTail()),
        ] else
          SizedBox(height: 420, child: const QueueView()),
      ],
    );
  }
}

class _QueueRow extends ConsumerWidget {
  const _QueueRow(this.i);
  final int i;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Tty.of(context);
    final st = ref.watch(playbackStateProvider);
    final item = st.queue[i];
    final current = i == st.index;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: current ? c.border : Colors.transparent)),
      ),
      child: TtyRow(
        dense: true,
        leading: SizedBox(
          width: 24,
          child: Text(
            current ? '▶' : (i - st.index + 1).toString().padLeft(2, '0'),
            style: TextStyle(color: current ? c.green : c.muted),
          ),
        ),
        title: item.track.title.toLowerCase(),
        titleColor: current ? c.green : null,
        subtitle:
            '${item.track.artist.toLowerCase()} · ${current ? 'en cours' : formatDuration(item.track.duration)}'
            '${current ? '' : queueSourceSuffix(item)}',
        onTap: () => ref.read(playbackControllerProvider).jumpTo(i),
        trailing: current
            ? null
            : IconButton(
                tooltip: 'Retirer',
                icon: Text('×', style: TextStyle(color: c.muted)),
                onPressed: () => ref.read(playbackControllerProvider).removeAt(i),
              ),
      ),
    );
  }
}

/// The play queue: tap to jump, drag to reorder, swipe to remove.
class QueueView extends ConsumerWidget {
  const QueueView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(playbackStateProvider);
    final pc = ref.read(playbackControllerProvider);
    final c = Tty.of(context);
    if (st.queue.isEmpty) return const Center(child: Comment('la file est vide'));
    return ReorderableListView.builder(
      footer: const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 16), child: QueueTail()),
      buildDefaultDragHandles: false,
      itemCount: st.queue.length,
      onReorderItem: pc.move,
      itemBuilder: (context, i) {
        final item = st.queue[i];
        final current = i == st.index;
        return Dismissible(
          key: ValueKey(item.uid),
          direction: current ? DismissDirection.none : DismissDirection.endToStart,
          background: Container(
            color: c.tint(c.red),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            child: Text('× retirer', style: TextStyle(color: c.red)),
          ),
          onDismissed: (_) => pc.removeAt(i),
          child: Material(
            type: MaterialType.transparency,
            child: TtyRow(
              dense: true,
              leading: CoverImage(item.track.coverId, size: 36, label: item.track.artist, seed: item.track.albumId),
              title: item.track.title.toLowerCase(),
              titleColor: current ? c.green : null,
              bold: current,
              subtitle:
                  [
                    item.track.artist.toLowerCase(),
                    if (item.track.bpm != null) '${item.track.bpm!.round()} bpm',
                  ].join(' · ') +
                  queueSourceSuffix(item),
              onTap: () => pc.jumpTo(i),
              trailing: ReorderableDragStartListener(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('⠿', style: TextStyle(color: c.muted)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
