import 'package:material_ui/material_ui.dart';

import 'screens/album.dart';
import 'screens/artist.dart';
import 'screens/notifications.dart';
import 'screens/now_playing.dart';
import 'screens/playlist.dart';
import 'screens/playlists.dart';
import 'screens/releases.dart';
import 'screens/settings.dart';
import 'shell.dart';

// Navigation helpers. Detail pages open inside the current tab's navigator;
// the full player and settings cover the whole app.

void openAlbum(BuildContext context, int id) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AlbumScreen(id)));

void openArtist(BuildContext context, int id) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtistScreen(id)));

void openPlaylist(BuildContext context, int id) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaylistScreen(id)));

void openFolder(BuildContext context, int id) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaylistsScreen(folderId: id)));

void openReleases(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReleasesScreen()));

void openNowPlaying(BuildContext context, {bool lyrics = false}) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => NowPlayingScreen(showLyrics: lyrics)));

void openSettings(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

/// The bell: a page of the home tab on desktop, the whole screen on
/// mobile (with the shell's scope, so that its rows can open pages).
void openNotifications(BuildContext context) {
  final shell = ShellScope.of(context);
  if (MediaQuery.sizeOf(context).width >= desktopWidth) {
    shell?.open(homeTab, const NotificationsScreen());
    return;
  }
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      builder: (_) => shell == null
          ? const NotificationsScreen()
          : ShellScope(
              open: shell.open,
              select: shell.select,
              setBackHandler: shell.setBackHandler,
              child: const NotificationsScreen(),
            ),
    ),
  );
}

/// The playlist tree from its root, with the create/rename/move/reorder tools.
void openFolderRoot(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlaylistsScreen()));
