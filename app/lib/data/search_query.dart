import 'models.dart';

/// A search input split into its words and the filters typed as prefixes:
/// `bpm:>120`, `bpm:<90`, `bpm:90-120`, `bpm:118` (±3), `ton:8A`,
/// `ton:am`, `ton:f#m`, `ton:c` (key names give their Camelot code).
/// Unknown or malformed prefixes stay in the text.
typedef ParsedSearch = ({String text, SearchFilter filter});

ParsedSearch parseSearch(String input) {
  var filter = const SearchFilter();
  final words = <String>[];
  for (final word in input.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final lower = word.toLowerCase();
    if (lower.startsWith('bpm:')) {
      final range = parseBpm(lower.substring(4));
      if (range != null) {
        filter = filter.copyWith(bpmMin: () => range.$1, bpmMax: () => range.$2);
        continue;
      }
    } else if (lower.startsWith('ton:')) {
      final code = camelotOf(word.substring(4));
      if (code != null) {
        filter = filter.copyWith(camelot: () => code);
        continue;
      }
    }
    words.add(word);
  }
  return (text: words.join(' '), filter: filter);
}

/// "\>120", "<90", "90-120" (or "90–120"), "118" (118 ± 3). The bpm are
/// stored with one decimal: "\>120" starts at 120.1.
(double?, double?)? parseBpm(String v) {
  double? n(String s) {
    final d = double.tryParse(s.trim());
    return d != null && d > 0 && d < 1000 ? d : null;
  }

  for (final (op, lo) in const [('>=', true), ('<=', false), ('>', true), ('<', false)]) {
    if (!v.startsWith(op)) continue;
    final d = n(v.substring(op.length));
    if (d == null) return null;
    final step = op.length == 1 ? 0.1 : 0.0; // strict: one decimal past it
    return lo ? (d + step, null) : (null, d - step);
  }
  final parts = v.split(RegExp('[-–]'));
  if (parts.length == 2) {
    final (lo, hi) = (n(parts[0]), n(parts[1]));
    return lo != null && hi != null && lo <= hi ? (lo, hi) : null;
  }
  final d = n(v);
  return d == null ? null : (d - 3, d + 3);
}

const _minor = ['g#', 'd#', 'a#', 'f', 'c', 'g', 'd', 'a', 'e', 'b', 'f#', 'c#']; // 1A..12A
const _major = ['b', 'f#', 'c#', 'g#', 'd#', 'a#', 'f', 'c', 'g', 'd', 'a', 'e']; // 1B..12B
const _flats = {'ab': 'g#', 'eb': 'd#', 'bb': 'a#', 'db': 'c#', 'gb': 'f#'};

/// The Camelot code of "8A", "8a", "am", "a#m", "bbm", "c"; null otherwise.
String? camelotOf(String v) {
  final s = v.trim().toLowerCase().replaceAll('♯', '#').replaceAll('♭', 'b');
  final code = RegExp(r'^(\d{1,2})([ab])$').firstMatch(s);
  if (code != null) {
    final n = int.parse(code[1]!);
    return n >= 1 && n <= 12 ? '$n${code[2]!.toUpperCase()}' : null;
  }
  final key = RegExp(r'^([a-g][#b]?)(m?)$').firstMatch(s);
  if (key == null) return null;
  final tonic = _flats[key[1]] ?? key[1]!;
  final minor = key[2] == 'm';
  final i = (minor ? _minor : _major).indexOf(tonic);
  return i < 0 ? null : '${i + 1}${minor ? 'A' : 'B'}';
}
