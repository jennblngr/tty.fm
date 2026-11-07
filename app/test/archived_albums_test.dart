import 'package:flutter_test/flutter_test.dart';
import 'package:ttyfm/data/models.dart';
import 'package:ttyfm/state/library.dart';

Track _t(int id, int albumId) =>
    Track(id: id, title: 't$id', artistId: 1, artist: 'a', albumId: albumId, album: 'al$albumId', durationMs: 1000);

Album _a(int id) => Album(id: id, title: 'al$id', artistId: 1, artist: 'a');

void main() {
  final tracks = [_t(1, 10), _t(2, 10), _t(3, 20), _t(4, 20), _t(5, 30)];

  test('an album is archived only when all its tracks are', () {
    expect(fullyArchivedAlbums(tracks, {1, 2, 3}), {10});
    expect(fullyArchivedAlbums(tracks, {1, 2, 3, 4, 5}), {10, 20, 30});
    expect(fullyArchivedAlbums(tracks, {}), isEmpty);
  });

  test('ids of unknown tracks archive nothing', () {
    expect(fullyArchivedAlbums(tracks, {99}), isEmpty);
  });

  test('archived albums leave the list, the order stays', () {
    final albums = [_a(30), _a(10), _a(20)];
    expect(withoutArchived(albums, {10}).map((a) => a.id), [30, 20]);
    expect(withoutArchived(albums, const {}), same(albums));
  });
}
