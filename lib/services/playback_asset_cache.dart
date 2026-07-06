import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../domain/media_asset.dart';
import '../domain/song.dart';

/// 播放周期缓存 — 下载歌曲媒体文件到本地临时目录。
///
/// 切歌或 App 退出时调用 [clear] 清理。
class PlaybackAssetCache {
  PlaybackAssetCache({
    required String baseUrl,
    Directory? cacheDir,
    http.Client? httpClient,
  })  : _baseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
        _cacheDir = cacheDir ?? Directory.systemTemp.createTempSync('kirakara_cache_'),
        _http = httpClient ?? http.Client();

  final String _baseUrl;
  final Directory _cacheDir;
  final http.Client _http;

  /// 确保歌由 assets 已下载。完成后回填 [MediaAsset.cachedPath] 和
  /// [song.lyricProject.cachedPath]。
  Future<void> ensureSongAssets(Song song) async {
    for (final asset in song.assets) {
      await _ensureOne(song.id, asset);
    }
    // KRL 下载后同步更新 lyricProject.cachedPath
    for (final a in song.assets) {
      if (a.type == MediaAssetType.lyric && a.cachedPath != null) {
        song.lyricProject.cachedPath = a.cachedPath;
        break;
      }
    }
  }

  Future<void> _ensureOne(String songId, MediaAsset asset) async {
    // 已有有效本地文件，跳过
    if (asset.cachedPath != null && asset.cachedPath!.isNotEmpty) {
      final f = File(asset.cachedPath!);
      if (await f.exists()) return;
    }

    // 本地 file:// 无需下载
    if (asset.uri.isScheme('file')) {
      asset.cachedPath = asset.uri.toFilePath(windows: Platform.isWindows);
      return;
    }

    // 相对路径 → HTTP 下载
    final uriStr = asset.uri.toString();
    final url = uriStr.startsWith('http')
        ? uriStr
        : '$_baseUrl${uriStr.replaceFirst(RegExp(r'^/'), '')}';

    final ext = p.extension(asset.uri.path);
    final localPath = p.join(_cacheDir.path, '${songId}_${asset.type.name}$ext');

    try {
      final response = await _http.get(Uri.parse(url));
      if (response.statusCode != 200) return;

      await File(localPath).writeAsBytes(response.bodyBytes);
      asset.cachedPath = localPath;
    } catch (_) {
      // 下载失败，asset.cachedPath 保持 null
    }
  }

  /// 清理所有缓存文件。
  void clear() {
    try {
      if (_cacheDir.existsSync()) {
        _cacheDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  }

  void dispose() {
    _http.close();
  }
}
