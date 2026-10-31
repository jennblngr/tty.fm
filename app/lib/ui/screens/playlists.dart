import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/library.dart';
import '../dialogs.dart';
import '../format.dart';
import '../nav.dart';
import '../widgets/async_view.dart';
import '../widgets/cover.dart';

/// One level of the playlist tree: sub-folders first, then playlists.
/// [folderId] null is the root.
class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key, this.folderId});
  final int? folderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(playlistTreeProvider);
    final actions = ref.read(playlistActionsProvider);
    final folder = tree.value?.folder(folderId);
    final missing = folderId != null && tree.hasValue && folder == null; // deleted meanwhile

    return Scaffold(
      appBar: AppBar(title: Text(folderId == null ? 'Playlists' : folder?.name ?? '')),
      floatingActionButton: missing
          ? null
          : FloatingActionButton(
              tooltip: 'Créer',
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                useRootNavigator: true,
                builder: (ctx) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ListTile(
                      leading: const Icon(Icons.playlist_add),
                      title: const Text('Nouvelle playlist'),
                      onTap: () async {
                        Navigator.pop(ctx);
                        final name = await promptText(context, title: 'Nouvelle playlist', action: 'Créer');
                        if (name != null && context.mounted) {
                          await guard(context, () => actions.createPlaylist(name, folderId));
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.create_new_folder_outlined),
                      title: const Text('Nouveau dossier'),
                      onTap: () async {
                        Navigator.pop(ctx);
                        final name = await promptText(context, title: 'Nouveau dossier', action: 'Créer');
                        if (name != null && context.mounted) {
                          await guard(context, () => actions.createFolder(name, folderId));
                        }
                      },
                    ),
                  ]),
                ),
              ),
              child: const Icon(Icons.add),
            ),
      body: AsyncView(tree, onRetry: () => ref.invalidate(playlistTreeProvider), builder: (tree) {
        if (missing) return const Center(child: Text('Ce dossier n\'existe plus'));
        final folders = folder?.folders ?? tree.folders;
        final playlists = folder?.playlists ?? tree.playlists;
        if (folders.isEmpty && playlists.isEmpty) {
          return const Center(child: Text('Vide. Créez une playlist ou un dossier avec +'));
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(playlistTreeProvider.future),
          child: ListView(children: [
            for (final f in folders) _FolderTile(f, tree),
            for (final p in playlists) _PlaylistTile(p, tree),
            const SizedBox(height: 80),
          ]),
        );
      }),
    );
  }
}

class _FolderTile extends ConsumerWidget {
  const _FolderTile(this.folder, this.tree);
  final Folder folder;
  final PlaylistTree tree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(playlistActionsProvider);
    final count = folder.folders.length + folder.playlists.length;
    return ListTile(
      leading: const SizedBox(width: 48, height: 48, child: Icon(Icons.folder, size: 36)),
      title: Text(folder.name),
      subtitle: Text('$count élément${count > 1 ? 's' : ''}'),
      onTap: () => openFolder(context, folder.id),
      trailing: PopupMenuButton<VoidCallback>(
        onSelected: (a) => a(),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: () async {
              final name = await promptText(context, title: 'Renommer', initial: folder.name);
              if (name != null && context.mounted) await guard(context, () => actions.renameFolder(folder.id, name));
            },
            child: const Text('Renommer'),
          ),
          PopupMenuItem(
            value: () async {
              final dest = await pickFolder(context, tree, exclude: tree.subtree(folder.id));
              if (dest != null && context.mounted) {
                await guard(context, () => actions.moveFolder(folder.id, dest.folderId));
              }
            },
            child: const Text('Déplacer…'),
          ),
          PopupMenuItem(
            value: () async {
              if (await confirm(context, 'Supprimer « ${folder.name} » ?',
                      'Le dossier, ses sous-dossiers et toutes leurs playlists seront supprimés.') &&
                  context.mounted) {
                await guard(context, () => actions.deleteFolder(folder.id));
              }
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

class _PlaylistTile extends ConsumerWidget {
  const _PlaylistTile(this.playlist, this.tree);
  final Playlist playlist;
  final PlaylistTree tree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(playlistActionsProvider);
    return ListTile(
      leading: PlaylistCover(playlist.coverIds, size: 48),
      title: Text(playlist.name),
      subtitle: Text(formatCountDuration(playlist.trackCount, playlist.durationMs)),
      onTap: () => openPlaylist(context, playlist.id),
      trailing: PopupMenuButton<VoidCallback>(
        onSelected: (a) => a(),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: () async {
              final name = await promptText(context, title: 'Renommer', initial: playlist.name);
              if (name != null && context.mounted) {
                await guard(context, () => actions.renamePlaylist(playlist.id, name));
              }
            },
            child: const Text('Renommer'),
          ),
          PopupMenuItem(
            value: () async {
              final dest = await pickFolder(context, tree);
              if (dest != null && context.mounted) {
                await guard(context, () => actions.movePlaylist(playlist.id, dest.folderId));
              }
            },
            child: const Text('Déplacer…'),
          ),
          PopupMenuItem(
            value: () async {
              if (await confirm(context, 'Supprimer « ${playlist.name} » ?', 'Les morceaux restent dans la bibliothèque.') &&
                  context.mounted) {
                await guard(context, () => actions.deletePlaylist(playlist.id));
              }
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}
