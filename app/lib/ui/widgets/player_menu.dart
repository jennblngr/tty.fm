import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_repository.dart';
import '../../data/models.dart';
import '../../state/library.dart';
import '../../state/search.dart';
import '../nav.dart';
import '../screens/devices.dart';
import '../shell.dart';
import '../theme.dart';
import 'async_view.dart';
import 'cover.dart';
import 'tty.dart';

/// "[···]" of the player header: actions on the current track that the
/// screen does not already offer (Menus-Contextuels, fiche 01; Lecteur-Menu
/// 02b; Desktop-Lecteur D2). Groups in the order naviguer › régler ›
/// fichier › bibliothèque. Phone: panel from the bottom; desktop: menu
/// under the button, aligned right. Grey when closed, green while open.
///
/// Not here yet: radio, égaliseur, infos du fichier, modifier les tags,
/// archiver, retirer de la bibliothèque (#15).
class PlayerMenuButton extends ConsumerStatefulWidget {
  const PlayerMenuButton(this.track, {super.key});
  final Track track;

  @override
  ConsumerState<PlayerMenuButton> createState() => _PlayerMenuButtonState();
}

/// Desktop shortcuts shown in the menu, handled by [PlayerMenuShortcuts].
const _albumKey = SingleActivator(LogicalKeyboardKey.keyA, alt: true);
const _artistKey = SingleActivator(LogicalKeyboardKey.keyR, alt: true);

/// ⌥A / ⌥R on the desktop player: go to the album / artist of the track.
class PlayerMenuShortcuts extends StatelessWidget {
  const PlayerMenuShortcuts({super.key, required this.track, required this.child});
  final Track track;
  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      _albumKey: () => _leave(context, (ctx) => openAlbum(ctx, track.albumId)),
      _artistKey: () => _leave(context, (ctx) => openArtist(ctx, track.artistId)),
    },
    child: Focus(autofocus: true, child: child),
  );
}

/// Closes the player, then opens a library page from where it was.
void _leave(BuildContext screen, void Function(BuildContext) open) {
  final nav = Navigator.of(screen);
  nav.pop();
  open(nav.context);
}

class _PlayerMenuButtonState extends ConsumerState<PlayerMenuButton> {
  var _open = false;

  Track get track => widget.track;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final wide = MediaQuery.sizeOf(context).width >= desktopWidth;
    return Semantics(
      button: true,
      label: "Plus d'options",
      expanded: _open,
      excludeSemantics: true,
      child: InkWell(
        onTap: _show,
        borderRadius: BorderRadius.circular(4),
        hoverColor: Colors.transparent,
        child: Padding(
          // Phone: 12 px above and below, as in 02.
          padding: EdgeInsets.symmetric(vertical: wide ? 0 : 12),
          child: Text('[···]', style: TextStyle(color: _open ? c.green : c.muted)),
        ),
      ),
    );
  }

  Future<void> _show() async {
    final screen = context;
    final hidden = ref.read(hiddenTracksProvider).value?.contains(track.id) ?? false;
    final wide = MediaQuery.sizeOf(screen).width >= desktopWidth;
    final phone = Platform.isAndroid || Platform.isIOS;
    void setHidden(bool on) => guard(screen, () => ref.read(hiddenTracksProvider.notifier).set(track.id, on));
    final groups = <List<_Entry>>[
      [
        _Entry("aller à l'album", wide ? '⌥A' : '›', () => _leave(screen, (ctx) => openAlbum(ctx, track.albumId))),
        _Entry("aller à l'artiste", wide ? '⌥R' : '›', () => _leave(screen, (ctx) => openArtist(ctx, track.artistId))),
      ],
      [_Entry('lire sur…', phone ? 'ce tel. ›' : 'cet ordi ›', () => showDevicesSheet(screen))],
      [
        _Entry(
          "relancer l'analyse",
          null,
          () => guard(screen, () async {
            await ref.read(libraryProvider).resetAnalysis(track.id);
            ref.invalidate(analysisProvider(track.id));
          }, success: 'Analyse relancée'),
        ),
      ],
      [
        hidden
            ? _Entry('désarchiver', null, () => setHidden(false))
            : _Entry('archiver', null, () {
                setHidden(true);
                toastUndo(screen, '« ${track.title.toLowerCase()} » archivé.', () => setHidden(false));
              }),
      ],
    ];
    setState(() => _open = true);
    final action = wide ? await _dropdown(groups) : await _panel(groups);
    if (mounted) setState(() => _open = false);
    action?.call();
  }

  /// D2: 280 px, 8 px under the button, right edges aligned; fade and 4 px
  /// slide in 120 ms. Escape or a click outside closes it.
  Future<VoidCallback?> _dropdown(List<List<_Entry>> groups) {
    final c = Tty.of(context);
    final box = context.findRenderObject()! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final screenWidth = MediaQuery.sizeOf(context).width;
    return showGeneralDialog<VoidCallback>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fermer le menu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      transitionBuilder: (_, a, _, child) => FadeTransition(
        opacity: a,
        child: AnimatedBuilder(
          animation: a,
          builder: (_, child) => Transform.translate(offset: Offset(0, -4 * (1 - a.value)), child: child),
          child: child,
        ),
      ),
      pageBuilder: (menu, _, _) => Stack(
        children: [
          Positioned(
            top: rect.bottom + 8,
            right: screenWidth - rect.right,
            width: 280,
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [BoxShadow(color: Color(0x66000000), offset: Offset(0, 12), blurRadius: 32)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, g) in groups.indexed) ...[
                      if (i > 0) Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: c.border),
                      for (final e in g)
                        InkWell(
                          onTap: () => Navigator.pop(menu, e.action),
                          hoverColor: c.border,
                          splashFactory: NoSplash.splashFactory,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: _EntryRow(e),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 02b: panel from the bottom over a dimmed screen, the track on top and
  /// one block per group.
  Future<VoidCallback?> _panel(List<List<_Entry>> groups) {
    final c = Tty.of(context);
    return showModalBottomSheet<VoidCallback>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: c.surface,
      barrierColor: const Color(0xB811111B), // rgba(17, 17, 27, 0.72)
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheet) {
        final bottom = MediaQuery.viewPaddingOf(sheet).bottom;
        Widget group(List<_Entry> g, {required bool last}) => Container(
          padding: EdgeInsets.only(top: 4, bottom: last ? 0 : 4),
          decoration: last
              ? null
              : BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.border)),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final e in g)
                InkWell(
                  onTap: () => Navigator.pop(sheet, e.action),
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: _EntryRow(e)),
                ),
            ],
          ),
        );
        return Padding(
          // 32 px at the bottom, more if the system bar is taller.
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottom > 32 ? bottom : 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: c.empty, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Container(
                padding: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.border)),
                ),
                child: Row(
                  children: [
                    CoverImage(track.coverId, size: 40, radius: 4, label: track.artist, seed: track.albumId),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title.toLowerCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.green),
                          ),
                          Comment('${track.artist.toLowerCase()} · ${track.album.toLowerCase()}', maxLines: 1),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              for (final (i, g) in groups.indexed) group(g, last: i == groups.length - 1),
            ],
          ),
        );
      },
    );
  }
}

class _Entry {
  const _Entry(this.label, this.hint, this.action);
  final String label;
  final String? hint; // grey, on the right: "›", "⌥A", "ce tel. ›"
  final VoidCallback action;
}

class _EntryRow extends StatelessWidget {
  const _EntryRow(this.e);
  final _Entry e;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    const style = TextStyle(fontSize: 13, height: 1.5);
    return Row(
      children: [
        Expanded(
          child: Text(e.label, style: style.copyWith(color: c.text)),
        ),
        if (e.hint != null) Text(e.hint!, style: style.copyWith(color: c.muted)),
      ],
    );
  }
}
