import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import '../data/models.dart';
import '../state/library.dart';
import '../state/search.dart';
import 'shell.dart';
import 'theme.dart';
import 'widgets/tty.dart';

/// The home header's "// message du jour" (Entete-Variantes.dc.html): one
/// line of at most [maxLength] characters, "//" included, picked by
/// priority: P1 ongoing info › P2 news › P3 stat › P4 moment. Among the
/// eligible P3/P4, a draw at app start, never the same twice in a row.
/// Nothing eligible: "bonjour." or "bonsoir." alone.
///
/// Variants needing data the app doesn't have yet (audio analysis, mixes,
/// release tracking, rétro) are left out until it exists.
class DailyMessage {
  const DailyMessage(this.id, this.pre, [this.highlight = '', this.post = '', this.tone = Tone.green, this.seed = 0]);

  final String id;
  final String pre;
  final String highlight; // the dynamic part, in colour
  final String post;
  final Tone tone;
  final int seed; // for [Tone.accent]

  String get text => '// $pre$highlight$post';

  Color color(Tty c) => switch (tone) {
    Tone.green => c.green,
    Tone.peach => c.peach,
    Tone.teal => c.teal,
    Tone.accent => c.accentFor(seed),
  };

  /// "pre", "highlight" (coloured) and "post", the "// " left to [Comment].
  List<InlineSpan> spans(Tty c) => [
    TextSpan(text: pre),
    if (highlight.isNotEmpty)
      TextSpan(
        text: highlight,
        style: TextStyle(color: color(c)),
      ),
    TextSpan(text: post),
  ];
}

/// Numbers in green, names in the colour of their element, as on the mockup.
enum Tone { green, peach, teal, accent }

const maxLength = 45;

/// Track count milestones celebrated for a day ("5 000 titres dans ta biblio").
const milestones = [1000, 2500, 5000, 10000, 25000, 50000, 100000];

/// Picks the message. [seed] makes the P3/P4 draw stable for a session,
/// [previousId] is the one shown last time.
DailyMessage pickDailyMessage({
  required DateTime now,
  required HomeData home,
  DateTime? lastOpen,
  ListeningStats? month,
  ListeningStats? last30,
  int? milestone,
  String? previousId,
  int seed = 0,
}) {
  final salut = greeting(now);

  // P1: nothing to listen to yet.
  if (home.recentlyAdded.isEmpty) return DailyMessage('biblio.vide', '$salut. bibliothèque vide.');

  // P2: albums added since the last opening (the last week the first time).
  final since = lastOpen ?? now.subtract(const Duration(days: 7));
  final added = home.recentlyAdded.where((a) => a.addedAt != null && a.addedAt!.isAfter(since)).length;
  if (added > 0) {
    final s = added > 1 ? 's' : '';
    return DailyMessage('ajouts.recents', '', '$added', ' ajout$s récent$s.');
  }

  final moments = home.moments;
  final anniversary = moments.anniversary;
  final evening = moments.eveningGenre;
  final pool = <DailyMessage>[
    // P3
    if (moments.streakDays >= 3 && moments.streakDays >= moments.streakRecord)
      DailyMessage('serie.record', '', '${moments.streakDays} jours', " d'écoute d'affilée. record !"),
    if (month != null && now.day >= 7 && month.totalMs >= 3600000) _month(month),
    // P4
    if (now.hour >= 18 && evening != null && evening.isNotEmpty)
      _fit(DailyMessage('moment.soir', 'bonsoir. un peu de ', evening.toLowerCase(), ' pour finir ?', Tone.teal)),
    if (now.hour < 5) DailyMessage('moment.nuit', 'il est ${now.hour}h. nuit calme, ', '< 90 bpm', ' ?', Tone.peach),
    if (anniversary != null)
      _fit(
        DailyMessage(
          'souvenir.decouverte',
          'il y a ${anniversary.years} an${anniversary.years > 1 ? 's' : ''}, tu découvrais ',
          anniversary.artist.toLowerCase(),
          '.',
          Tone.accent,
          anniversary.artistId,
        ),
      ),
    if (last30 != null && last30.topTracks.isNotEmpty && last30.topTracks.first.$2 > 30)
      _fit(
        DailyMessage(
          'clin-oeil.repeat',
          '',
          last30.topTracks.first.$1.title.toLowerCase(),
          ' : ${last30.topTracks.first.$2} écoutes. on change ?',
          Tone.accent,
          last30.topTracks.first.$1.albumId,
        ),
      ),
    if (milestone != null) DailyMessage('palier.biblio', '', _thousands(milestone), ' titres dans ta biblio.'),
  ];
  if (pool.length > 1) pool.removeWhere((m) => m.id == previousId);
  if (pool.isEmpty) return DailyMessage('repli.salut', '$salut.');
  return pool[Random(seed).nextInt(pool.length)];
}

DailyMessage _month(ListeningStats s) {
  final prev = s.prevTotalMs;
  final pct = prev == null || prev == 0 ? null : ((s.totalMs - prev) * 100 / prev).round();
  final trend = pct == null || pct == 0 ? '' : ' ${pct > 0 ? '↑' : '↓'}${pct.abs()}%.';
  return DailyMessage('stats.mois', '', '${(s.totalMs / 3600000).round()}h', ' ce mois-ci.$trend');
}

/// Shortens the highlighted name so that the line holds in [maxLength].
DailyMessage _fit(DailyMessage m) {
  final over = m.text.length - maxLength;
  if (over <= 0) return m;
  final keep = max(1, m.highlight.length - over - 1);
  final h = '${m.highlight.substring(0, keep).trimRight()}…';
  return DailyMessage(m.id, m.pre, h, m.post, m.tone, m.seed);
}

String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ' '); // 5 000

/// The highest milestone reached by [tracks] if it was crossed less than a
/// day ago. [stored] is (milestone, when) from the previous check; the first
/// check only records the count, an existing library isn't a news.
(int? show, (int, DateTime)? store) checkMilestone(int tracks, (int, DateTime)? stored, DateTime now) {
  final reached = milestones.lastWhere((m) => tracks >= m, orElse: () => 0);
  if (stored == null) return (null, (reached, DateTime(2000)));
  if (reached > stored.$1) return (reached, (reached, now));
  final fresh = stored.$1 > 0 && now.difference(stored.$2) < const Duration(days: 1);
  return (fresh ? stored.$1 : null, null);
}

/// Read once at startup: the previous opening and message, and a seed for
/// the draw. Stores this opening for the next time.
final _sessionProvider = Provider<({DateTime? lastOpen, String? previousId, int seed})>((ref) {
  final p = ref.read(sharedPrefsProvider);
  final last = p.getInt('homeLastOpen');
  p.setInt('homeLastOpen', DateTime.now().millisecondsSinceEpoch);
  return (
    lastOpen: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
    previousId: p.getString('homeMessage'),
    seed: Random().nextInt(1 << 31),
  );
});

final dailyMessageProvider = Provider.autoDispose<DailyMessage?>((ref) {
  final home = ref.watch(homeProvider).value;
  if (home == null) return null;
  final now = DateTime.now();
  final session = ref.watch(_sessionProvider);
  final p = ref.read(sharedPrefsProvider);

  int? milestone;
  final tracks = ref.watch(libraryStatsProvider).value?.tracks;
  if (tracks != null) {
    final at = p.getInt('homeMilestoneAt');
    final stored = at == null ? null : (p.getInt('homeMilestone') ?? 0, DateTime.fromMillisecondsSinceEpoch(at));
    final (show, store) = checkMilestone(tracks, stored, now);
    milestone = show;
    if (store != null) {
      p.setInt('homeMilestone', store.$1);
      p.setInt('homeMilestoneAt', store.$2.millisecondsSinceEpoch);
    }
  }

  final m = pickDailyMessage(
    now: now,
    home: home,
    lastOpen: session.lastOpen,
    // Rolling days since the 1st: the month so far.
    month: now.day >= 7 ? ref.watch(statsProvider(now.day)).value : null,
    last30: ref.watch(statsProvider(30)).value,
    milestone: milestone,
    previousId: session.previousId,
    seed: session.seed,
  );
  p.setString('homeMessage', m.id);
  return m;
});
