import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_info.dart';
import '../../data/models.dart';
import '../../core/network.dart';
import '../../offline/downloads.dart';
import '../../state/remote.dart';
import '../../state/search.dart';
import '../nav.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/async_view.dart';
import '../widgets/tty.dart';
import 'devices.dart';
import 'offline.dart';

/// Period choices of the stats page, in days (0 = all time).
const _periods = [(7, '7j'), (30, '30j'), (90, '90j'), (0, 'tout')];

class _Period extends Notifier<int> {
  @override
  int build() => 30;
  void set(int days) => state = days;
}

final _periodProvider = NotifierProvider<_Period, int>(_Period.new);

/// "$ stats": listening time per weekday, top artists and genres, highlights.
/// On phones it is also the "whoami" page with shortcuts to the settings.
/// Tempo statistics come with the audio analysis (phase 3).
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(_periodProvider);
    final stats = ref.watch(statsProvider(days));
    final wide = MediaQuery.sizeOf(context).width >= desktopWidth;
    final label = _periods.firstWhere((p) => p.$1 == days).$2;

    final periods = Wrap(
      spacing: 6,
      children: [
        for (final (d, l) in _periods)
          TtyLink(l, active: d == days, onTap: () => ref.read(_periodProvider.notifier).set(d)),
      ],
    );

    return AsyncView(
      stats,
      onRetry: () => ref.invalidate(statsProvider(days)),
      builder: (s) {
        final panels = s.plays == 0
            ? <Widget>[const Comment('aucune écoute sur cette période.')]
            : <Widget>[
                _ListeningTime(s, label),
                _TopArtists(s, label),
                _TopGenres(s, label),
                _TempoPanel(s, label),
                _Highlights(s, label),
              ];
        return TtyPage(
          gap: 20,
          onRefresh: () => ref.refresh(statsProvider(days).future),
          children: [
            TtyPrompt(wide ? 'stats' : 'whoami', brand: wide ? null : appDisplayName, trailing: periods),
            if (wide) TtyGrid(minWidth: 360, spacing: 20, children: panels) else ...panels,
            if (!wide) const _Shortcuts(),
          ],
        );
      },
    );
  }
}

String _minutes(int ms) => '${(ms / 60000).round()} min';

String _hours(int ms) {
  final h = ms / 3600000;
  return h >= 10 ? '${h.round()}h' : '${h.toStringAsFixed(1)}h';
}

class _ListeningTime extends StatelessWidget {
  const _ListeningTime(this.s, this.period);
  final ListeningStats s;
  final String period;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    const days = ['lu', 'ma', 'me', 'je', 've', 'sa', 'di'];
    final top = s.weekdayAvgMin.fold<int>(0, (m, v) => v > m ? v : m);
    final prev = s.prevTotalMs;
    final trend = prev == null || prev == 0 ? null : ((s.totalMs - prev) / prev * 100).round();
    return TtyPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TtySection("temps d'écoute [$period]", glyph: '▮', color: c.blue),
          const Comment('minutes moyennes par jour'),
          const SizedBox(height: 8),
          for (var i = 0; i < 7; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(days[i], style: TextStyle(color: c.muted)),
                  ),
                  Expanded(
                    child: _DottedBar(
                      value: top == 0 ? 0 : s.weekdayAvgMin[i] / top,
                      color: s.weekdayAvgMin[i] == top && top > 0 ? c.green : c.blue,
                    ),
                  ),
                  SizedBox(width: 72, child: Text('${s.weekdayAvgMin[i]} min', textAlign: TextAlign.right)),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'total: ',
                  style: TextStyle(color: c.muted),
                ),
                TextSpan(
                  text: '${_hours(s.totalMs)}${trend == null ? '' : ' ${trend >= 0 ? '↑' : '↓'}${trend.abs()}%'}',
                  style: TextStyle(color: trend != null && trend < 0 ? c.peach : c.green),
                ),
                TextSpan(
                  text: ' · titres différents: ',
                  style: TextStyle(color: c.muted),
                ),
                TextSpan(
                  text: '${s.distinctTracks}',
                  style: TextStyle(color: c.green),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bar over a dotted track, as in the design.
class _DottedBar extends StatelessWidget {
  const _DottedBar({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    return SizedBox(
      height: 14,
      child: CustomPaint(
        painter: _DotsPainter(c.border),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0),
          child: ColoredBox(color: color),
        ),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (double x = 0; x < size.width; x += 4) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 2, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}

class _TopArtists extends StatelessWidget {
  const _TopArtists(this.s, this.period);
  final ListeningStats s;
  final String period;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final top = s.topArtists.isEmpty ? 1 : s.topArtists.first.ms;
    return TtyPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TtySection('top artistes [$period]', glyph: '✦', color: c.mauve),
          const SizedBox(height: 6),
          for (var i = 0; i < s.topArtists.length; i++)
            () {
              final a = s.topArtists[i];
              final color = c.accentFor(a.id ?? i);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${(i + 1).toString().padLeft(2, '0')} '),
                            TextSpan(
                              text: a.name.toLowerCase(),
                              style: TextStyle(color: color),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TtyMeter(a.ms / top, color: color, suffix: _minutes(a.ms)),
                  ],
                ),
              );
            }(),
        ],
      ),
    );
  }
}

class _TopGenres extends StatelessWidget {
  const _TopGenres(this.s, this.period);
  final ListeningStats s;
  final String period;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final total = s.topGenres.fold<int>(0, (a, g) => a + g.ms);
    return TtyPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TtySection('top genres [$period]', glyph: '▦', color: c.pink),
          const SizedBox(height: 6),
          if (s.topGenres.isEmpty) const Comment('aucun genre dans les tags des titres écoutés'),
          for (var i = 0; i < s.topGenres.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${s.topGenres[i].name.toLowerCase()} '),
                          miniGraphSpan(sparkline(s.topGenres[i].name.hashCode, length: 4)),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.accents[(i + 1) % c.accents.length]),
                    ),
                  ),
                  Text(
                    '${(s.topGenres[i].ms * 100 / (total == 0 ? 1 : total)).round()}%',
                    style: TextStyle(color: c.muted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "∿ tempo": how the listening time spreads over the tempo bands, the
/// mean bpm and its trend, the fastest and slowest tracks played, morning
/// against evening (05, D5). Analysed tracks only.
class _TempoPanel extends StatelessWidget {
  const _TempoPanel(this.s, this.period);
  final ListeningStats s;
  final String period;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final t = s.tempo;
    final total = t.analyzedMs == 0 ? 1 : t.analyzedMs;
    final top = t.bandMs.fold<int>(1, (a, b) => b > a ? b : a);
    InlineSpan value(String v, [Color? color]) => TextSpan(
      text: v,
      style: TextStyle(color: color ?? c.text),
    );
    Widget line(String k, List<InlineSpan> v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$k: ',
              style: TextStyle(color: c.muted),
            ),
            ...v,
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    String bpm(double v) => '${v.round()}';
    final avg = t.avgBpm, prev = t.prevAvgBpm;
    final trend = avg != null && prev != null && avg != prev
        ? ' ${avg > prev ? '↑' : '↓'}${(avg - prev).abs().round()}'
        : '';
    final (morning, evening) = (t.morningBpm, t.eveningBpm);
    return TtyPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TtySection('tempo [$period]', glyph: '∿', color: c.peach, comment: 'répartition de tes écoutes par bpm'),
          const SizedBox(height: 6),
          if (t.analyzedMs == 0)
            const Comment('aucun titre analysé parmi tes écoutes')
          else ...[
            for (var i = 0; i < Tempo.bands.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(Tempo.bands[i], style: TextStyle(color: c.muted)),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TtyMeter(t.bandMs[i] / top, color: c.peach),
                      ),
                    ),
                    Text('${(t.bandMs[i] * 100 / total).round()}%', style: TextStyle(color: c.muted)),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            if (avg != null) line('bpm moyen', [value(bpm(avg), c.peach), value(trend, c.muted)]),
            if (t.fastest case final f?)
              line('le + rapide', [value(f.title.toLowerCase()), value(' — ${f.bpm?.round()} bpm', c.muted)]),
            if (t.slowest case final f? when f.id != t.fastest?.id)
              line('le + lent', [value(f.title.toLowerCase()), value(' — ${f.bpm?.round()} bpm', c.muted)]),
            if (morning != null && evening != null && morning.round() != evening.round())
              Comment(
                morning > evening
                    ? 'plus rapide le matin (${bpm(morning)}) que le soir (${bpm(evening)})'
                    : 'plus rapide le soir (${bpm(evening)}) que le matin (${bpm(morning)})',
              ),
          ],
        ],
      ),
    );
  }
}

class _Highlights extends StatelessWidget {
  const _Highlights(this.s, this.period);
  final ListeningStats s;
  final String period;

  static String _hourNick(int h) => switch (h) {
    >= 22 || < 5 => 'oiseau de nuit',
    < 9 => 'lève-tôt',
    < 14 => 'midi en musique',
    < 18 => "l'après-midi",
    _ => 'en soirée',
  };

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    Widget line(String k, InlineSpan v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$k: ',
              style: TextStyle(color: c.muted),
            ),
            v,
          ],
        ),
      ),
    );
    final top = s.topTracks.firstOrNull;
    return TtyPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TtySection('temps forts [$period]', glyph: '★', color: c.yellow),
          const SizedBox(height: 6),
          if (top != null)
            line(
              'titre le + écouté',
              TextSpan(
                text: '${top.$1.title.toLowerCase()} — ${top.$2} fois',
                style: TextStyle(color: c.blue),
              ),
            ),
          if (s.topGenres.isNotEmpty) line('genre n°1', TextSpan(text: s.topGenres.first.name.toLowerCase())),
          if (s.favoriteHour != null)
            line(
              'heure favorite',
              TextSpan(
                children: [
                  TextSpan(
                    text: '${s.favoriteHour}h',
                    style: TextStyle(color: c.peach),
                  ),
                  TextSpan(
                    text: ' // ${_hourNick(s.favoriteHour!)}',
                    style: TextStyle(color: c.muted),
                  ),
                ],
              ),
            ),
          if (s.discovery != null)
            line(
              'découverte',
              TextSpan(
                text: s.discovery!.name.toLowerCase(),
                style: TextStyle(color: c.teal),
              ),
            ),
          line('écoutes', TextSpan(text: '${s.plays}')),
        ],
      ),
    );
  }
}

/// Phone-only shortcuts below the stats ("$ apparence", …), as in the design.
class _Shortcuts extends ConsumerWidget {
  const _Shortcuts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Tty.of(context);
    final others = ref.watch(remoteDevicesProvider.select((r) => r.devices.length));
    final offline = ref.watch(downloadsProvider.select((s) => s.tracks.length));
    final quality = ref.watch(streamQualityProvider);
    Widget item(String label, String? value, VoidCallback onTap) => InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: Row(
          children: [
            Text('\$ ', style: TextStyle(color: c.green)),
            Expanded(child: Text(label)),
            if (value != null) Text(value, style: TextStyle(color: c.muted)),
            Text('  ›', style: TextStyle(color: c.muted)),
          ],
        ),
      ),
    );
    return Column(
      children: [
        item('réglages', quality.label.toLowerCase(), () => openSettings(context)),
        item('appareils', others == 0 ? 'aucun autre' : '$others dispo', () => showDevicesSheet(context)),
        item(
          'hors-ligne',
          '$offline titres',
          () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(appBar: AppBar(), body: const OfflineList()),
            ),
          ),
        ),
      ],
    );
  }
}
