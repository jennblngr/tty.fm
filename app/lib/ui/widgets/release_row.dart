import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../format.dart';
import '../links.dart';
import '../nav.dart';
import '../theme.dart';
import 'cover.dart';
import 'tty.dart';

/// A new release ("● nouvelles sorties"): "[✓]" in green when the library
/// has it, and a tap opens the album; otherwise a tap opens the artist and
/// "[+]" opens the release on MusicBrainz.
class ReleaseRow extends StatelessWidget {
  const ReleaseRow(this.release, {super.key});
  final NewRelease release;

  @override
  Widget build(BuildContext context) {
    final c = Tty.of(context);
    final r = release;
    return TtyRow(
      leading: CoverImage(null, size: 44, label: r.artist, seed: r.artistId),
      title: r.title.toLowerCase(),
      titleColor: c.teal,
      subtitle: newReleaseSubtitle(r),
      trailing: r.albumId != null
          ? Text('[✓]', style: TextStyle(color: c.green))
          : r.mbid.isEmpty
          ? null
          : TtyLink(
              '+',
              tooltip: 'voir sur MusicBrainz',
              onTap: () => openLink(context, musicBrainzReleaseGroup(r.mbid)),
            ),
      onTap: () => r.albumId != null ? openAlbum(context, r.albumId!) : openArtist(context, r.artistId),
    );
  }
}

/// "charlotte cardin · album · à venir le 29 janv. 2027", "sia · single ·
/// sorti le 20 août" (the year only when it is not the current one).
String newReleaseSubtitle(NewRelease r, {DateTime? now}) {
  final d = r.date;
  final year = (now ?? DateTime.now()).year;
  String day(DateTime d) {
    final s = formatDate(d);
    return d.year == year ? s.substring(0, s.length - 5) : s;
  }

  final String? when;
  if (d == null) {
    when = null;
  } else if (r.released.length == 7) {
    // Only the month is known: "sorti en août", "à venir en janv. 2027".
    final month = day(d).split(' ').skip(1).join(' ');
    when = '${r.upcoming ? 'à venir' : 'sorti'} en $month';
  } else {
    when = '${r.upcoming ? 'à venir le' : 'sorti le'} ${day(d)}';
  }
  return [r.artist.toLowerCase(), if (r.kind == 'ep') 'EP' else r.kind, ?when].join(' · ');
}
