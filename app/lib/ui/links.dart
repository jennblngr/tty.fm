import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// Pages outside the app: what the library lacks (a new release, an artist
// to discover) is looked up there.

/// A release group on MusicBrainz (the "[+]" of a new release).
Uri musicBrainzReleaseGroup(String mbid) => Uri.https('musicbrainz.org', '/release-group/$mbid');

/// An artist on ListenBrainz ("◇ à découvrir").
Uri listenBrainzArtist(String mbid) => Uri.https('listenbrainz.org', '/artist/$mbid/');

/// Opens [uri] in the browser, with a message when nothing can open it.
Future<void> openLink(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok) messenger?.showSnackBar(SnackBar(content: Text("impossible d'ouvrir ${uri.host}")));
}
