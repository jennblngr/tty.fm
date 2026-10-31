import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../state/library.dart';
import 'widgets/async_view.dart';
import 'widgets/cover.dart';

/// Asks for a single line of text (names). Returns null if cancelled.
Future<String?> promptText(BuildContext context, {required String title, String initial = '', String action = 'OK'}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(action)),
      ],
    ),
  ).then((v) => v == null || v.isEmpty ? null : v);
}

Future<bool> confirm(BuildContext context, String title, String message, {String action = 'Supprimer'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    ) ??
    false;

/// Result of the folder picker: [folderId] null means the root.
class FolderChoice {
  const FolderChoice(this.folderId);
  final int? folderId;
}

/// Lets the user pick a destination folder. Folders in [exclude] (a folder
/// and its descendants when moving a folder) are not selectable.
Future<FolderChoice?> pickFolder(BuildContext context, PlaylistTree tree, {Set<int> exclude = const {}}) {
  return showDialog<FolderChoice>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Déplacer vers…'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, const FolderChoice(null)),
          child: const ListTile(leading: Icon(Icons.home_outlined), title: Text('Racine')),
        ),
        for (final (f, depth) in tree.flatten())
          SimpleDialogOption(
            onPressed: exclude.contains(f.id) ? null : () => Navigator.pop(ctx, FolderChoice(f.id)),
            child: Padding(
              padding: EdgeInsets.only(left: 16.0 * (depth + 1)),
              child: ListTile(
                enabled: !exclude.contains(f.id),
                leading: const Icon(Icons.folder_outlined),
                title: Text(f.name),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Bottom sheet listing all playlists (with their folder path) plus a
/// "new playlist" entry; adds [tracks] to the chosen one.
Future<void> addToPlaylist(BuildContext context, WidgetRef ref, List<Track> tracks) async {
  final ids = [for (final t in tracks) t.id];
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final tree = ref.watch(playlistTreeProvider);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (ctx, scroll) => AsyncView(
            tree,
            builder: (tree) {
              final entries = <(Playlist, String)>[
                for (final p in tree.playlists) (p, ''),
                for (final (f, _) in tree.flatten())
                  for (final p in f.playlists) (p, _folderPath(tree, f)),
              ];
              return ListView(
                controller: scroll,
                children: [
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Nouvelle playlist'),
                    onTap: () async {
                      final name = await promptText(ctx, title: 'Nouvelle playlist', action: 'Créer');
                      if (name == null || !ctx.mounted) return;
                      Navigator.pop(ctx);
                      await guard(
                        context,
                        () => ref.read(playlistActionsProvider).createPlaylist(name, null, ids),
                        success: 'Ajouté à « $name »',
                      );
                    },
                  ),
                  const Divider(),
                  for (final (p, path) in entries)
                    ListTile(
                      leading: PlaylistCover(p.coverIds, size: 40),
                      title: Text(p.name),
                      subtitle: path.isEmpty ? null : Text(path),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await guard(
                          context,
                          () => ref.read(playlistActionsProvider).addTracks(p.id, ids),
                          success: 'Ajouté à « ${p.name} »',
                        );
                      },
                    ),
                ],
              );
            },
          ),
        );
      },
    ),
  );
}

String _folderPath(PlaylistTree tree, Folder f) {
  final parts = <String>[f.name];
  var parent = tree.folder(f.parentId);
  while (parent != null) {
    parts.insert(0, parent.name);
    parent = tree.folder(parent.parentId);
  }
  return parts.join(' › ');
}
