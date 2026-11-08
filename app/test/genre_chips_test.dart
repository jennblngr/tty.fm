import 'package:flutter_test/flutter_test.dart';
import 'package:ttyfm/ui/screens/now_playing.dart';

void main() {
  const analysed = [('électro', 0.68), ('Dance-pop', 0.24)];

  test('the tag comes first, then the style the analysis heard', () {
    expect(genreChips('Pop', analysed), ['pop', 'dance-pop']);
  });

  test('a tag listing several genres gives its first one', () {
    expect(genreChips('Pop;Films/Jeux vidéo;Musiques de films', analysed), ['pop', 'dance-pop']);
    expect(genreChips('Indie Pop / Neo Soul / Funk / R&B', const []), ['indie pop']);
  });

  test('without a tag, the genre and style of the analysis', () {
    expect(genreChips(null, analysed), ['électro', 'dance-pop']);
    expect(genreChips('  ', analysed), ['électro', 'dance-pop']);
  });

  test('a style equal to the tag is not repeated; nothing gives no chip', () {
    expect(genreChips('dance-pop', analysed), ['dance-pop']);
    expect(genreChips(null, const []), isEmpty);
  });
}
