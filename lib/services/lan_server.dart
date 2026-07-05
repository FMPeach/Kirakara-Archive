import 'dart:convert';
import 'dart:io';

import '../domain/song.dart';
import 'queue_service.dart';
import 'search_service.dart';

class LanServer {
  LanServer({
    required QueueService queueService,
    required SearchService searchService,
  })  : _queueService = queueService,
        _searchService = searchService;

  final QueueService _queueService;
  final SearchService _searchService;
  HttpServer? _server;

  bool get isRunning => _server != null;
  Uri? get localUri {
    final server = _server;
    if (server == null) {
      return null;
    }
    return Uri.parse('http://${server.address.host}:${server.port}');
  }

  Future<void> start({int port = 7391}) async {
    if (_server != null) {
      return;
    }

    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handleRequest);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers
      ..contentType = ContentType.json
      ..add('Access-Control-Allow-Origin', '*');

    if (request.method == 'GET' && request.uri.path == '/api/search') {
      final query = request.uri.queryParameters['q'] ?? '';
      final songs = await _searchService.search(query);
      request.response.write(jsonEncode(songs.map(_songToJson).toList()));
      await request.response.close();
      return;
    }

    if (request.method == 'POST' && request.uri.path == '/api/queue') {
      final body = await utf8.decoder.bind(request).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      final songId = payload['songId'] as String?;
      final matches = _searchService.featuredSongs.where(
        (candidate) => candidate.id == songId,
      );
      final song = matches.isEmpty ? null : matches.first;
      if (song == null) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'error': 'song_not_found'}));
      } else {
        final item = _queueService.addSong(song, requestedBy: '手机点歌');
        request.response.write(jsonEncode({'queueId': item.id}));
      }
      await request.response.close();
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    request.response.write(jsonEncode({'error': 'not_found'}));
    await request.response.close();
  }

  Map<String, Object?> _songToJson(Song song) {
    return {
      'id': song.id,
      'title': song.title,
      'artist': song.artist.name,
      'category': song.category,
      'code': song.code,
    };
  }
}
