import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/notifications.dart';
import '../../state/notifications.dart';
import '../nav.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/async_view.dart';
import '../widgets/tty.dart';
import 'album.dart';

/// "$ notifications" (07, D7): grouped by day, newest first. Mobile: full
/// screen with [fermer] and [tout lu]; desktop: a page of the home tab.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationsProvider.notifier);
    final wide = MediaQuery.sizeOf(context).width >= desktopWidth;
    final c = Tty.of(context);

    return AsyncView(
      list,
      onRetry: () => ref.invalidate(notificationsProvider),
      builder: (l) {
        final now = DateTime.now();
        final unread = l.unread;
        final count = unread == 0 ? 'rien de nouveau' : '$unread non lue${unread > 1 ? 's' : ''}';
        final readAll = TtyLink(
          wide ? 'tout marquer lu' : 'tout lu',
          color: unread == 0 ? c.muted : c.green,
          onTap: unread == 0 ? null : () => guard(context, notifier.readAll),
        );

        final sections = <String, List<AppNotification>>{};
        for (final n in l.items) {
          sections.putIfAbsent(notificationSection(n.createdAt, now), () => []).add(n);
        }

        final children = <Widget>[
          if (wide)
            TtyPrompt(
              'notifications',
              comment: count,
              trailing: Row(
                children: [
                  TtyLink('réglages', onTap: () => openSettings(context)),
                  const SizedBox(width: 16),
                  readAll,
                ],
              ),
            )
          else
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '// $count. réglables dans '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: InkWell(
                      onTap: () => openSettings(context),
                      child: Text('\$ réglages', style: TextStyle(color: c.green)),
                    ),
                  ),
                ],
              ),
              style: TextStyle(color: c.muted),
            ),
          if (l.items.isEmpty) const Comment('les ajouts à la bibliothèque apparaîtront ici.'),
          for (final MapEntry(key: title, value: items) in sections.entries)
            _Section(title, items, now: now, muted: title == 'cette semaine' || title == 'plus ancien'),
        ];

        final body = ListView.separated(
          padding: wide ? const EdgeInsets.fromLTRB(32, 24, 32, 32) : const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: children.length,
          separatorBuilder: (_, _) => SizedBox(height: wide ? 32 : 24),
          itemBuilder: (_, i) => children[i],
        );
        final refreshable = RefreshIndicator(onRefresh: () => ref.refresh(notificationsProvider.future), child: body);
        if (wide) return Scaffold(body: SafeArea(child: refreshable));

        // Header of 07: three columns, the title centred on the screen.
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TtyLink('fermer', onTap: () => Navigator.pop(context)),
                        ),
                      ),
                      Text(
                        '\$ notifications',
                        style: TextStyle(color: c.mauve, fontWeight: FontWeight.w700),
                      ),
                      Expanded(
                        child: Align(alignment: Alignment.centerRight, child: readAll),
                      ),
                    ],
                  ),
                ),
                Expanded(child: refreshable),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.items, {required this.now, required this.muted});
  final String title;
  final List<AppNotification> items;
  final DateTime now;
  final bool muted; // older sections: greyed title

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 8),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w700, color: muted ? c.muted : null),
          ),
        ),
        for (final n in items) _Row(n, now: now),
      ],
    );
  }
}

/// "[ ] + 3 titres ajoutés — faune, racines" / "// 2 albums · 21h14". The
/// box toggles read; the row opens what it is about and marks it read.
class _Row extends ConsumerWidget {
  const _Row(this.n, {required this.now});
  final AppNotification n;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Tty.of(context);
    final notifier = ref.read(notificationsProvider.notifier);
    final fg = n.read ? c.muted : c.text;
    final (head, rest) = notificationTitle(n);
    final link = n.albumId != null ? "voir l'album" : 'voir dans la biblio';

    void open() {
      if (!n.read) guard(context, () => notifier.setRead(n.id, true));
      final id = n.albumId;
      final shell = ShellScope.of(context);
      if (MediaQuery.sizeOf(context).width < desktopWidth) Navigator.pop(context);
      if (id != null) {
        shell?.open(homeTab, AlbumScreen(id));
      } else {
        shell?.select(biblioTab);
      }
    }

    return InkWell(
      onTap: open,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => guard(context, () => notifier.setRead(n.id, !n.read)),
              child: Text(
                n.read ? '[✓]' : '[ ]',
                semanticsLabel: n.read ? 'Marquer non lue' : 'Marquer lue',
                style: TextStyle(color: n.read ? c.green : c.muted),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: head,
                          style: TextStyle(color: n.read ? null : c.yellow),
                        ),
                        if (rest != null) TextSpan(text: ' — $rest'),
                      ],
                    ),
                    style: TextStyle(color: fg),
                  ),
                  Text(notificationDetail(n, now), style: TextStyle(color: c.muted)),
                  if (!n.read) Text('[$link]', style: TextStyle(color: c.green)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- wording ---------------------------------------------------------------

/// Title of a notification: the coloured head, and what follows the dash.
(String, String?) notificationTitle(AppNotification n) {
  final s = n.tracks > 1 ? 's' : '';
  final names = [for (final a in n.artists) a.toLowerCase()];
  final more = n.artistCount - names.length;
  return ('+ ${n.tracks} titre$s ajouté$s', names.isEmpty ? null : '${names.join(', ')}${more > 0 ? ' +$more' : ''}');
}

/// "// 2 albums · 21h14".
String notificationDetail(AppNotification n, DateTime now) =>
    '// ${n.albums} album${n.albums > 1 ? 's' : ''} · ${notificationWhen(n.createdAt, now)}';

int _daysAgo(DateTime t, DateTime now) =>
    DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;

/// "aujourd'hui", "hier", "cette semaine" or "plus ancien".
String notificationSection(DateTime t, DateTime now) => switch (_daysAgo(t, now)) {
  <= 0 => "aujourd'hui",
  1 => 'hier',
  < 7 => 'cette semaine',
  _ => 'plus ancien',
};

const _weekdays = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

/// "21h14" today and yesterday, "mar." this week, "24 oct." before.
String notificationWhen(DateTime t, DateTime now) => switch (_daysAgo(t, now)) {
  <= 1 => '${t.hour}h${t.minute.toString().padLeft(2, '0')}',
  < 7 => _weekdays[t.weekday - 1],
  _ => '${t.day} ${_months[t.month - 1]}',
};
