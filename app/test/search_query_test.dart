import 'package:flutter_test/flutter_test.dart';
import 'package:ttyfm/data/models.dart';
import 'package:ttyfm/data/search_query.dart';
import 'package:ttyfm/ui/screens/search.dart';

void main() {
  test('bpm prefixes become a tempo range', () {
    expect(parseBpm('>120'), (120.1, null));
    expect(parseBpm('>=120'), (120.0, null));
    expect(parseBpm('<90'), (null, 89.9));
    expect(parseBpm('90-120'), (90.0, 120.0));
    expect(parseBpm('90–120'), (90.0, 120.0));
    expect(parseBpm('118'), (115.0, 121.0));
    for (final bad in ['', '>', 'fast', '120-90', '0', '-5']) {
      expect(parseBpm(bad), isNull, reason: bad);
    }
  });

  test('keys: Camelot codes and key names', () {
    expect(camelotOf('8A'), '8A');
    expect(camelotOf('8a'), '8A');
    expect(camelotOf('12b'), '12B');
    expect(camelotOf('am'), '8A');
    expect(camelotOf('C'), '8B');
    expect(camelotOf('f#m'), '11A');
    expect(camelotOf('bbm'), '3A');
    expect(camelotOf('E♭'), '5B');
    for (final bad in ['13A', '0B', 'h', 'la mineur', '8C']) {
      expect(camelotOf(bad), isNull, reason: bad);
    }
  });

  test('parseSearch takes the prefixes out of the words', () {
    final p = parseSearch('néons bpm:>120 ton:am  kid');
    expect(p.text, 'néons kid');
    expect(p.filter.bpmMin, 120.1);
    expect(p.filter.bpmMax, isNull);
    expect(p.filter.camelot, '8A');
    expect(p.filter.toQuery(), {'bpm_min': 120.1, 'camelot': '8A'});

    final kept = parseSearch('bpm:vite ton:zz');
    expect(kept.text, 'bpm:vite ton:zz');
    expect(kept.filter.isActive, isFalse);
  });

  test('a typed prefix wins over the chip of the same kind', () {
    const chips = SearchFilter(genre: 'pop', bpmMin: 140, camelot: '1A');
    final f = chips.merge(parseSearch('bpm:<90').filter);
    expect((f.genre, f.bpmMin, f.bpmMax, f.camelot), ('pop', null, 89.9, '1A'));
  });

  test('the bpm bands and key names of the chips', () {
    expect(bpmBands.map((b) => b.$1), ['<90', '90–120', '120–140', '>140']);
    expect(camelotCodes, hasLength(24));
    expect(camelotName('8A'), 'la mineur');
    expect(camelotName('8B'), 'do majeur');
    for (final code in camelotCodes) {
      expect(camelotOf(code), code);
    }
  });
}
