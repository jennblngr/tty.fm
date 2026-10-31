import 'package:flutter/material.dart';

import 'screens/album.dart';
import 'screens/artist.dart';
import 'screens/now_playing.dart';
import 'screens/playlist.dart';
import 'screens/playlists.dart';
import 'screens/settings.dart';

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

void openNowPlaying(BuildContext context) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const NowPlayingScreen()));

void openSettings(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
