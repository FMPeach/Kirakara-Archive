import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../domain/media_asset.dart';
import '../domain/song.dart';

/// 播放周期缓存 — 下载歌曲媒体文件到本地临时目录。
///
/// 切歌或 App 退出时调用 [clear] 清理。
class PlaybackAssetCache extends ChangeNotifier {
  PlaybackAssetCache({
    required String baseUrl,
    Directory? cacheDir,
    http.Client? httpClient,
    http.Client? mediaHttpClient,
  })  : _baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
        _cacheDir =
            cacheDir ?? Directory.systemTemp.createTempSync('kirakara_cache_'),
        _http = httpClient ?? http.Client(),
        _mediaHttp = mediaHttpClient ?? http.Client();

  final Uri _baseUri;
  final Directory _cacheDir;
  final http.Client _http;
  final http.Client _mediaHttp;
  final Map<String, Future<void>> _downloads = {};
  final Map<String, MediaAsset> _streamAssets = {};
  final Map<String, _DownloadState> _downloadStates = {};
  final _AsyncPermitPool _videoDownloadPool = _AsyncPermitPool(3);
  HttpServer? _streamServer;
  Future<HttpServer>? _streamServerFuture;
  bool _disposed = false;

  String get cacheDirectoryPath => _cacheDir.path;

  Future<int> cacheSizeBytes() async {
    if (!await _cacheDir.exists()) return 0;
    var total = 0;
    await for (final entity in _cacheDir.list(recursive: true)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          // A progressive file may be moving from .part while we inspect it.
        }
      }
    }
    return total;
  }

  /// 确保歌曲全部 assets 完整下载。完成后回填 [MediaAsset.cachedPath] 和
  /// [song.lyricProject.cachedPath]。
  Future<void> ensureSongAssets(Song song) async {
    await Future.wait(song.assets.map(_ensureOne));
    _syncLyricProject(song);
  }

  /// 播放前准备：KRL 等小资源和音频完整缓存；视频同时启动后台渐进缓存。
  ///
  /// 当前 Show 音频链路仍需要先拿到完整音频再解码，因此 vocal/inst 仍然
  /// 会被等待。视频只有在尚未完整落盘时才注册本机渐进缓存入口。
  Future<void> ensurePlaybackAssets(
    Song song, {
    bool awaitAudio = true,
  }) async {
    final blocking = <Future<void>>[];
    final videos = <MediaAsset>[];
    for (final asset in song.assets) {
      if (!_isPlaybackAsset(asset)) continue;
      if (asset.type == MediaAssetType.video) {
        videos.add(asset);
        unawaited(_ensureOne(asset, background: true));
      } else if (_isAudio(asset.type)) {
        final task = _ensureOne(asset);
        if (awaitAudio) {
          blocking.add(task);
        } else {
          unawaited(task);
        }
      } else {
        blocking.add(_ensureOne(asset));
      }
    }
    final streamVideos = videos
        .where((asset) => existingLocalPathFor(asset) == null)
        .toList(growable: false);
    if (streamVideos.isNotEmpty) {
      await _ensureStreamServer();
      for (final asset in streamVideos) {
        _registerStreamAsset(asset);
      }
    }
    await Future.wait(blocking);
    _syncLyricProject(song);
  }

  /// 队列预热用：歌词、原唱、伴奏和视频都并发启动下载，调用方不等待。
  ///
  /// 这个方法不等待音频完成，专门给“队列里后续歌曲”提前占坑。播放真正
  /// 落到这首歌时，[ensurePlaybackAssets] 会复用同一个下载任务并等待
  /// 音频/KRL 等必要资源完整落盘。
  void prefetchPlaybackAssets(Song song) {
    final videos = <MediaAsset>[];
    for (final asset in song.assets) {
      if (!_isPlaybackAsset(asset)) continue;
      if (asset.type == MediaAssetType.video) {
        videos.add(asset);
      }
      unawaited(_ensureOne(asset, background: true));
    }
    final streamVideos = videos
        .where((asset) => existingLocalPathFor(asset) == null)
        .toList(growable: false);
    if (streamVideos.isNotEmpty) {
      unawaited(_ensureStreamServer().then((_) {
        for (final asset in streamVideos) {
          _registerStreamAsset(asset);
        }
      }));
    }
  }

  /// 队列预热用：所有资源并发启动下载，调用方不等待。
  void prefetchSongAssets(Song song) {
    prefetchPlaybackAssets(song);
  }

  /// 设置歌曲下载优先级。保留接口给 UI/slot manager 调用；当前下载层只按
  /// asset/url 去重，不再做独占门控，避免播放中任务阻塞其它预热。
  void setSongPriority(String songId, int priority) {
    // no-op
  }

  /// 歌曲所有已知 asset 是否已完整缓存。
  bool isSongFullyCached(Song song) {
    if (song.assets.isEmpty) return true;
    for (final asset in song.assets) {
      final local = existingLocalPathFor(asset);
      if (local == null) return false;
    }
    // 没有正在进行的下载
    final inProgress = _downloads.keys
        .any((key) => song.assets.any((a) => key.startsWith('${a.id}|')));
    return !inProgress;
  }

  /// 歌曲级聚合下载进度。
  ({int total, int downloaded, bool complete}) songProgress(Song song) {
    var total = 0;
    var downloaded = 0;
    var complete = true;
    for (final asset in song.assets.where(_isPlaybackAsset)) {
      final p = _progressForAsset(asset);
      if (p.totalBytes != null) total += p.totalBytes!;
      downloaded += p.downloadedBytes;
      if (!p.isComplete) complete = false;
    }
    return (total: total, downloaded: downloaded, complete: complete);
  }

  /// 播放时优先返回完整缓存/本地文件；没有完整缓存时返回可流式读取的 HTTP URL。
  /// 视频统一走本地流服务器（即使已完整缓存），避免 MF 引擎直接读文件时
  /// 的文件系统瓶颈和缓冲不足问题。
  String? playbackPathFor(MediaAsset asset) {
    if (asset.type == MediaAssetType.video) {
      final streamUrl = _localStreamUrlFor(asset);
      if (streamUrl != null) return streamUrl;
      return _remoteUrlFor(asset);
    }
    final local = existingLocalPathFor(asset);
    if (local != null) return local;
    return _remoteUrlFor(asset);
  }

  /// 只返回已经完整存在的本地文件。音频和 KRL 当前需要走这里。
  String? existingLocalPathFor(MediaAsset asset) {
    final cached = asset.cachedPath;
    if (cached != null && cached.isNotEmpty && File(cached).existsSync()) {
      return cached;
    }
    if (asset.uri.isScheme('file')) {
      final path = asset.uri.toFilePath(windows: Platform.isWindows);
      return File(path).existsSync() ? path : null;
    }
    final local = _localPathFor(asset);
    if (File(local).existsSync()) {
      asset.cachedPath = local;
      return local;
    }
    return null;
  }

  PlaybackAssetProgress progressForSong(Song song) {
    var totalBytes = 0;
    var downloadedBytes = 0;
    var knownAssets = 0;
    var completeAssets = 0;
    var bytesPerSecond = 0.0;

    final assets = song.assets.where(_isPlaybackAsset).toList(growable: false);
    for (final asset in assets) {
      final progress = _progressForAsset(asset);
      if (progress.totalBytes != null && progress.totalBytes! > 0) {
        totalBytes += progress.totalBytes!;
        knownAssets++;
      }
      downloadedBytes += progress.downloadedBytes;
      bytesPerSecond += progress.bytesPerSecond;
      if (progress.isComplete) completeAssets++;
    }

    return PlaybackAssetProgress(
      totalBytes: totalBytes,
      downloadedBytes: totalBytes > 0
          ? downloadedBytes.clamp(0, totalBytes).toInt()
          : downloadedBytes,
      bytesPerSecond: bytesPerSecond,
      knownAssets: knownAssets,
      completeAssets: completeAssets,
      assetCount: assets.length,
    );
  }

  void _syncLyricProject(Song song) {
    final lp = song.lyricProject;
    if (lp != null) {
      for (final a in song.assets) {
        if (a.type == MediaAssetType.lyric && a.cachedPath != null) {
          lp.cachedPath = a.cachedPath;
          break;
        }
      }
    }
  }

  Future<void> _ensureOne(
    MediaAsset asset, {
    bool background = false,
  }) {
    // 已有有效本地文件，跳过
    if (asset.cachedPath != null && asset.cachedPath!.isNotEmpty) {
      final f = File(asset.cachedPath!);
      if (f.existsSync()) return Future.value();
    }

    // A completed progressive video can remain as `.part` while Media
    // Foundation still has the file open. Treat it as a finished cache entry
    // and retry the cosmetic rename without issuing another HTTP request.
    final completedPart = _completedPartFor(asset);
    if (completedPart != null) {
      return _promoteCompletedPart(asset, completedPart);
    }

    // 本地 file:// 无需下载
    if (asset.uri.isScheme('file')) {
      asset.cachedPath = asset.uri.toFilePath(windows: Platform.isWindows);
      return Future.value();
    }

    final url = _remoteUrlFor(asset);
    if (url == null) return Future.value();

    final localPath = _localPathFor(asset);
    final key = '${asset.id}|${asset.type.name}|${asset.version}|$url';
    final active = _downloads[key];
    if (active != null) {
      return active.then((_) => _hydrateCachedAsset(asset, localPath));
    }

    late final Future<void> future;
    future = _ensureOneDownload(
      url: url,
      localPath: localPath,
      asset: asset,
      client: background ? _mediaHttp : _http,
    ).whenComplete(() {
      if (identical(_downloads[key], future)) {
        _downloads.remove(key);
      }
    });
    _downloads[key] = future;
    return future;
  }

  Future<void> _ensureOneDownload({
    required String url,
    required String localPath,
    required MediaAsset asset,
    required http.Client client,
  }) async {
    if (asset.type != MediaAssetType.video) {
      if (await _hydrateCachedAsset(asset, localPath)) return;
      await _downloadToCache(url, localPath, asset, client: client);
      return;
    }

    final release = await _videoDownloadPool.acquire();
    try {
      if (await _hydrateCachedAsset(asset, localPath)) return;
      await _downloadToCache(url, localPath, asset, client: client);
    } finally {
      release();
    }
  }

  Future<bool> _hydrateCachedAsset(
    MediaAsset asset,
    String localPath,
  ) async {
    final localFile = File(localPath);
    if (!await localFile.exists()) return false;
    asset.cachedPath = localPath;
    final state = _downloadStateFor(asset);
    state.totalLength = await localFile.length();
    state.downloadedBytes = state.totalLength ?? 0;
    state.complete = true;
    return true;
  }

  String? _remoteUrlFor(MediaAsset asset) {
    if (asset.uri.isScheme('http') || asset.uri.isScheme('https')) {
      return asset.uri.toString();
    }
    if (asset.uri.hasScheme) return null;
    return _baseUri.resolveUri(asset.uri).toString();
  }

  String _localPathFor(MediaAsset asset) {
    final ext = p.extension(asset.uri.path).isEmpty
        ? '.bin'
        : p.extension(asset.uri.path);
    final safeId = asset.id.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]+'), '_');
    return p.join(
      _cacheDir.path,
      '${safeId}_${asset.type.name}_v${asset.version}$ext',
    );
  }

  Future<void> _downloadToCache(
    String url,
    String localPath,
    MediaAsset asset, {
    required http.Client client,
  }) async {
    try {
      final localFile = File(localPath);
      final partFile = File('$localPath.part');
      final state = _downloadStateFor(asset);
      await localFile.parent.create(recursive: true);

      var existingBytes = await partFile.exists() ? await partFile.length() : 0;
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(asset.headers);
      if (existingBytes > 0) {
        request.headers[HttpHeaders.rangeHeader] = 'bytes=$existingBytes-';
      }

      final response = await client.send(request);
      if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        if (existingBytes > 0) {
          state.complete = true;
          state.totalLength = existingBytes;
          state.downloadedBytes = state.totalLength ?? 0;
          _notifyProgressListeners();
          await _promoteCompletedPart(asset, partFile);
        }
        return;
      }
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        // 404/403/5xx — 资源不存在，标记跳过，不阻塞进度条
        await partFile.create(recursive: true);
        state.complete = true;
        state.totalLength = 0;
        state.downloadedBytes = 0;
        _notifyProgressListeners();
        return;
      }

      final append =
          response.statusCode == HttpStatus.partialContent && existingBytes > 0;
      if (!append) {
        existingBytes = 0;
      }

      state.totalLength = _expectedLength(response, existingBytes);
      state.downloadedBytes = existingBytes;
      state.complete = false;
      state.markSample(existingBytes);
      _notifyProgressListeners();

      final writer = await partFile.open(
        mode: append ? FileMode.append : FileMode.write,
      );
      try {
        await for (final chunk in response.stream) {
          await writer.writeFrom(chunk);
          state.downloadedBytes += chunk.length;
          state.markSample(state.downloadedBytes);
          _notifyProgressListeners();
        }
      } finally {
        await writer.close();
      }

      final expectedLength = _expectedLength(response, existingBytes);
      final actualLength = await partFile.length();
      if (expectedLength == null || actualLength >= expectedLength) {
        // Completion is defined by bytes on disk, not by whether Windows lets
        // us rename a file that MF is currently reading. Mark it complete
        // first so the queue cannot get stuck at 100% or download it twice.
        state.complete = true;
        state.totalLength = actualLength;
        state.downloadedBytes = actualLength;
        state.markSample(actualLength);
        _notifyProgressListeners();
        await _promoteCompletedPart(asset, partFile);
      }
    } catch (_) {
      // 下载失败，asset.cachedPath 保持 null
    }
  }

  Future<HttpServer> _ensureStreamServer() {
    final server = _streamServer;
    if (server != null) return Future.value(server);
    final pending = _streamServerFuture;
    if (pending != null) return pending;

    final future = HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((s) {
      _streamServer = s;
      s.listen(_handleStreamRequest);
      return s;
    });
    _streamServerFuture = future;
    return future;
  }

  String? _localStreamUrlFor(MediaAsset asset) {
    final server = _streamServer;
    if (server == null) return null;
    final token = _registerStreamAsset(asset);
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: ['cache', token],
    ).toString();
  }

  String _registerStreamAsset(MediaAsset asset) {
    final token = Uri.encodeComponent(
      '${asset.id}_${asset.type.name}_v${asset.version}',
    );
    _streamAssets[token] = asset;
    return token;
  }

  Future<void> _handleStreamRequest(HttpRequest request) async {
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }
      if (request.uri.pathSegments.length != 2 ||
          request.uri.pathSegments.first != 'cache') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final token = request.uri.pathSegments[1];
      final asset = _streamAssets[token];
      if (asset == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      // 不在此触发下载——视频下载由 ensurePlaybackAssets 统一管理

      final totalLength = await _waitForTotalLength(asset);
      if (totalLength == null || totalLength <= 0) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.headers.set(HttpHeaders.retryAfterHeader, '1');
        await request.response.close();
        return;
      }

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      final range = rangeHeader == null
          ? (start: 0, end: totalLength - 1, partial: false)
          : _parseRequestRange(rangeHeader, totalLength);
      if (range == null) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers
            .set(HttpHeaders.contentRangeHeader, 'bytes */$totalLength');
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        await request.response.close();
        return;
      }

      if (await _shouldProxyRemote(asset, range.start)) {
        await _proxyRemoteRange(
          request: request,
          asset: asset,
          rangeHeader: rangeHeader,
        );
        return;
      }

      final contentLength = range.end - range.start + 1;
      final contentType = _contentTypeFor(asset.uri.path);
      request.response.statusCode =
          range.partial ? HttpStatus.partialContent : HttpStatus.ok;
      request.response.headers.contentType = ContentType.parse(contentType);
      request.response.headers.contentLength = contentLength;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (range.partial) {
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes ${range.start}-${range.end}/$totalLength',
        );
      }

      if (request.method == 'HEAD') {
        await request.response.close();
        return;
      }

      await _writeCachedRange(
        response: request.response,
        asset: asset,
        start: range.start,
        end: range.end,
      );
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  ({int start, int end, bool partial})? _parseRequestRange(
    String header,
    int size,
  ) {
    final parsed = _parseRange(header, size);
    if (parsed == null) return null;
    return (start: parsed.start, end: parsed.end, partial: true);
  }

  ({int start, int end})? _parseRange(String header, int size) {
    if (!header.startsWith('bytes=') || size <= 0) return null;
    var spec = header.substring('bytes='.length);
    final comma = spec.indexOf(',');
    if (comma >= 0) spec = spec.substring(0, comma);
    spec = spec.trim();
    if (!spec.contains('-')) return null;
    final dash = spec.indexOf('-');
    final startText = spec.substring(0, dash);
    final endText = spec.substring(dash + 1);
    try {
      final int start;
      final int end;
      if (startText.isEmpty) {
        final suffix = int.parse(endText);
        if (suffix <= 0) return null;
        start = (size - suffix).clamp(0, size - 1);
        end = size - 1;
      } else {
        start = int.parse(startText);
        end = endText.isEmpty ? size - 1 : int.parse(endText);
      }
      if (start < 0 || start >= size || end < start) return null;
      return (start: start, end: end.clamp(start, size - 1));
    } on FormatException {
      return null;
    }
  }

  Future<int?> _waitForTotalLength(MediaAsset asset) async {
    final localFile = File(_localPathFor(asset));
    if (await localFile.exists()) return localFile.length();

    final state = _downloadStateFor(asset);
    for (var i = 0; i < 200; i++) {
      final known = state.totalLength;
      if (known != null && known > 0) return known;
      if (await localFile.exists()) return localFile.length();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return null;
  }

  Future<bool> _shouldProxyRemote(MediaAsset asset, int rangeStart) async {
    if (await File(_localPathFor(asset)).exists()) return false;
    final available = await _availableCachedBytes(asset);
    // MF may request MP4 tail metadata before the sequential download reaches
    // it. Do not block the local cache server for those far-ahead reads.
    const maxWaitAheadBytes = 512 * 1024;
    return rangeStart > available + maxWaitAheadBytes;
  }

  Future<int> _availableCachedBytes(MediaAsset asset) async {
    final file = await _readableFileFor(asset);
    return file == null ? 0 : file.length();
  }

  Future<void> _proxyRemoteRange({
    required HttpRequest request,
    required MediaAsset asset,
    required String? rangeHeader,
  }) async {
    final url = _remoteUrlFor(asset);
    if (url == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    final remoteRequest = http.Request('GET', Uri.parse(url));
    remoteRequest.headers.addAll(asset.headers);
    if (rangeHeader != null) {
      remoteRequest.headers[HttpHeaders.rangeHeader] = rangeHeader;
    }

    http.StreamedResponse? remoteResponse;
    try {
      remoteResponse = await _mediaHttp.send(remoteRequest);
      request.response.statusCode = remoteResponse.statusCode;
      final contentType = remoteResponse.headers[HttpHeaders.contentTypeHeader];
      if (contentType != null) {
        request.response.headers.contentType = ContentType.parse(contentType);
      }
      final contentLength = remoteResponse.contentLength;
      if (contentLength != null && contentLength >= 0) {
        request.response.headers.contentLength = contentLength;
      }
      for (final header in const [
        HttpHeaders.acceptRangesHeader,
        HttpHeaders.contentRangeHeader,
      ]) {
        final value = remoteResponse.headers[header];
        if (value != null) request.response.headers.set(header, value);
      }

      if (request.method == 'HEAD') {
        await request.response.close();
        return;
      }

      await for (final chunk in remoteResponse.stream) {
        request.response.add(chunk);
        await request.response.flush();
      }
      await request.response.close();
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _writeCachedRange({
    required HttpResponse response,
    required MediaAsset asset,
    required int start,
    required int end,
  }) async {
    final source = await _readableFileFor(asset);
    if (source == null) {
      await response.close();
      return;
    }

    final raf = await source.open();
    try {
      await raf.setPosition(start);
      var remaining = end - start + 1;
      const chunkSize = 256 * 1024;
      while (remaining > 0) {
        final currentLen = await source.length();
        final available = (currentLen - (start + (end - start + 1 - remaining)))
            .clamp(0, remaining);
        if (available <= 0) {
          // 数据还没下载到，等 100ms 再试（最多等 10 秒）
          var waited = 0;
          while (waited < 10000 && await source.length() <= currentLen) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            waited += 100;
          }
          continue;
        }
        final toRead = available > chunkSize ? chunkSize : available;
        final chunk = await raf.read(toRead);
        if (chunk.isEmpty) break;
        response.add(chunk);
        remaining -= chunk.length;
      }
      await response.flush();
    } finally {
      await raf.close();
    }
    await response.close();
  }

  Future<bool> _waitForReadableBytes(MediaAsset asset, int minBytes) async {
    for (var i = 0; i < 6000; i++) {
      final file = await _readableFileFor(asset);
      if (file != null && await file.length() >= minBytes) return true;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return false;
  }

  Future<File?> _readableFileFor(MediaAsset asset) async {
    final localFile = File(_localPathFor(asset));
    if (await localFile.exists()) return localFile;
    final partFile = File('${_localPathFor(asset)}.part');
    if (await partFile.exists()) return partFile;
    return null;
  }

  int? _expectedLength(http.StreamedResponse response, int existingBytes) {
    final contentRange = response.headers[HttpHeaders.contentRangeHeader];
    if (contentRange != null) {
      final match = RegExp(r'bytes\s+\d+-\d+/(\d+)', caseSensitive: false)
          .firstMatch(contentRange);
      if (match != null) return int.tryParse(match.group(1)!);
    }
    final contentLength = response.contentLength;
    if (contentLength == null || contentLength < 0) return null;
    return existingBytes + contentLength;
  }

  _DownloadState _downloadStateFor(MediaAsset asset) =>
      _downloadStates.putIfAbsent(_localPathFor(asset), _DownloadState.new);

  File? _completedPartFor(MediaAsset asset) {
    final state = _downloadStateFor(asset);
    if (!state.complete) return null;
    final partFile = File('${_localPathFor(asset)}.part');
    if (!partFile.existsSync()) return null;
    final length = partFile.lengthSync();
    final expected = state.totalLength;
    if (length <= 0 || (expected != null && length < expected)) return null;
    return partFile;
  }

  Future<void> _promoteCompletedPart(
    MediaAsset asset,
    File partFile,
  ) async {
    final localPath = _localPathFor(asset);
    final localFile = File(localPath);
    try {
      if (await localFile.exists()) {
        asset.cachedPath = localPath;
        return;
      }
      await partFile.rename(localPath);
      asset.cachedPath = localPath;
    } on FileSystemException {
      // The loopback stream may still be serving this file to MF. The `.part`
      // already contains the complete resource and remains the readable source
      // until a later ensure call can promote it.
    }
  }

  _AssetProgress _progressForAsset(MediaAsset asset) {
    if (asset.uri.isScheme('file')) {
      final path = asset.uri.toFilePath(windows: Platform.isWindows);
      final file = File(path);
      final length = file.existsSync() ? file.lengthSync() : 0;
      return _AssetProgress(
        totalBytes: length,
        downloadedBytes: length,
        bytesPerSecond: 0,
        isComplete: length > 0,
      );
    }

    final localFile = File(_localPathFor(asset));
    if (localFile.existsSync()) {
      final length = localFile.lengthSync();
      return _AssetProgress(
        totalBytes: length,
        downloadedBytes: length,
        bytesPerSecond: 0,
        isComplete: true,
      );
    }

    final partFile = File('${_localPathFor(asset)}.part');
    final state = _downloadStateFor(asset);
    final downloaded =
        partFile.existsSync() ? partFile.lengthSync() : state.downloadedBytes;
    return _AssetProgress(
      totalBytes: state.totalLength,
      downloadedBytes: downloaded,
      bytesPerSecond: state.bytesPerSecond,
      isComplete: state.complete,
    );
  }

  String _contentTypeFor(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.mp4':
        return 'video/mp4';
      case '.m4v':
        return 'video/x-m4v';
      case '.webm':
        return 'video/webm';
      case '.mov':
        return 'video/quicktime';
      default:
        return 'application/octet-stream';
    }
  }

  bool _isAudio(MediaAssetType type) =>
      type == MediaAssetType.vocal || type == MediaAssetType.accompaniment;

  bool _isPlaybackAsset(MediaAsset asset) => true; // include cover — 404 handled gracefully

  void _notifyProgressListeners() {
    if (!_disposed) notifyListeners();
  }

  /// 清理所有缓存文件。
  void clear() {
    try {
      if (_cacheDir.existsSync()) {
        _cacheDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _http.close();
    _mediaHttp.close();
    unawaited(_streamServer?.close(force: true));
    _streamServer = null;
    super.dispose();
  }
}

class _DownloadState {
  int? totalLength;
  int downloadedBytes = 0;
  double bytesPerSecond = 0;
  bool complete = false;
  int _lastSampleBytes = 0;
  DateTime? _lastSampleAt;

  void markSample(int bytes) {
    final now = DateTime.now();
    final lastAt = _lastSampleAt;
    if (lastAt != null) {
      final elapsed = now.difference(lastAt).inMilliseconds;
      final delta = bytes - _lastSampleBytes;
      if (elapsed >= 250 && delta >= 0) {
        bytesPerSecond = delta * 1000 / elapsed;
        _lastSampleAt = now;
        _lastSampleBytes = bytes;
      }
      return;
    }
    _lastSampleAt = now;
    _lastSampleBytes = bytes;
  }
}

class _AsyncPermitPool {
  _AsyncPermitPool(this._limit);

  final int _limit;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();
  int _active = 0;

  Future<void Function()> acquire() async {
    if (_active < _limit && _waiters.isEmpty) {
      _active++;
    } else {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    var released = false;
    return () {
      if (released) return;
      released = true;
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      } else {
        _active--;
      }
    };
  }
}

class PlaybackAssetProgress {
  const PlaybackAssetProgress({
    required this.totalBytes,
    required this.downloadedBytes,
    required this.bytesPerSecond,
    required this.knownAssets,
    required this.completeAssets,
    required this.assetCount,
  });

  final int totalBytes;
  final int downloadedBytes;
  final double bytesPerSecond;
  final int knownAssets;
  final int completeAssets;
  final int assetCount;

  double? get fraction =>
      totalBytes <= 0 ? null : (downloadedBytes / totalBytes).clamp(0.0, 1.0);

  bool get isComplete => assetCount > 0 && completeAssets >= assetCount;
}

class _AssetProgress {
  const _AssetProgress({
    required this.totalBytes,
    required this.downloadedBytes,
    required this.bytesPerSecond,
    required this.isComplete,
  });

  final int? totalBytes;
  final int downloadedBytes;
  final double bytesPerSecond;
  final bool isComplete;
}
