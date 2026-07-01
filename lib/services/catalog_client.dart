import '../domain/song.dart';

abstract class CatalogClient {
  Future<List<Song>> fetchUpdatedSongs({DateTime? since});
  Future<void> syncSongAssets(String songId);
}

class MockCatalogClient implements CatalogClient {
  const MockCatalogClient();

  @override
  Future<List<Song>> fetchUpdatedSongs({DateTime? since}) async {
    return const [];
  }

  @override
  Future<void> syncSongAssets(String songId) async {}
}
