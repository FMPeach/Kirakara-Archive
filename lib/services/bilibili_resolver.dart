import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/artist.dart';
import '../domain/media_asset.dart';
import '../domain/song.dart';

// ── Result types ──────────────────────────────────────────────────

class BilibiliPageInfo {
  const BilibiliPageInfo({
    required this.cid,
    required this.title,
    required this.page,
    required this.duration,
  });

  final int cid;
  final String title; // 分P标题
  final int page; // 分P序号 (1-indexed)
  final int duration; // 秒
}

class BilibiliResolveResult {
  const BilibiliResolveResult({
    required this.song,
    required this.bvid,
    required this.cid,
    required this.quality,
    required this.qualityDesc,
    required this.pages,
    required this.selectedPage,
    required this.ownerName,
    required this.ownerMid,
    required this.coverUrl,
    this.playCount,
    this.danmakuCount,
  });

  final Song song;
  final String bvid;
  final int cid;
  final int quality;
  final String qualityDesc;
  final List<BilibiliPageInfo> pages;
  final int selectedPage;
  final String ownerName;
  final int ownerMid;
  final String coverUrl;
  final int? playCount;
  final int? danmakuCount;
}

class BilibiliResolveError {
  const BilibiliResolveError({required this.code, required this.message});

  final String code; // 'network' | 'not_found' | 'no_stream' | 'parse'
  final String message;
}

// ── Constants ─────────────────────────────────────────────────────

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

const _referer = 'https://www.bilibili.com';

const _qualityMap = {
  6: '240P',
  16: '360P',
  32: '480P',
  64: '720P',
  74: '720P60',
  80: '1080P',
  112: '1080P+',
  116: '1080P60',
};

// ── AV → BV ──────────────────────────────────────────────────────

const _bvTable = 'fZodR9XQDSUm21yCkr6zBqiveYah8bt7xsWpVLHdJAjKFGnME';
const _bvS = [11, 10, 3, 8, 4, 6];
const _bvXor = 177451812;
const _bvAdd = 8728348608;

String avToBv(int av) {
  var x = (av ^ _bvXor) + _bvAdd;
  final r = List<String>.filled(12, '');
  for (var i = 0; i < 6; i++) {
    r[_bvS[i]] = _bvTable[x % 58];
    x ~/= 58;
  }
  return 'BV1${r[2]}${r[3]}${r[4]}${r[5]}${r[6]}${r[7]}${r[8]}${r[9]}${r[10]}${r[11]}';
}

// ── HTTP helpers ──────────────────────────────────────────────────

Future<_HttpResult> _get(Uri uri, {Map<String, String>? headers}) async {
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    final request = await client.getUrl(uri);
    request.headers.set('User-Agent', _userAgent);
    request.headers.set('Referer', _referer);
    headers?.forEach((k, v) => request.headers.set(k, v));
    final response = await request.close().timeout(
          const Duration(seconds: 15),
        );
    final body = await response.transform(utf8.decoder).join();
    client.close();
    return _HttpResult(response.statusCode, body);
  } catch (e) {
    return _HttpResult(-1, '');
  }
}

Future<_HttpResult> _getRedirect(Uri uri) async {
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    final request = await client.getUrl(uri);
    request.headers.set('User-Agent', _userAgent);
    request.followRedirects = false;
    final response = await request.close().timeout(
          const Duration(seconds: 10),
        );
    final location = response.headers.value('location');
    client.close();
    return _HttpResult(
      response.statusCode,
      location ?? '',
    );
  } catch (e) {
    return _HttpResult(-1, '');
  }
}

class _HttpResult {
  const _HttpResult(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

// ── Public API ────────────────────────────────────────────────────

/// 解析 B站链接或 BV/AV 号，返回可播放的 Song 对象。
///
/// 支持格式：完整链接、短链 b23.tv、纯 BV 号、纯 AV 号。
Future<BilibiliResolveResult> resolveBilibiliUrl(String input) async {
  // 1. Resolve short links
  var url = input.trim();
  if (url.contains('b23.tv')) {
    final result = await _getRedirect(Uri.parse(url));
    if (result.statusCode == 301 || result.statusCode == 302) {
      url = result.body;
    } else {
      throw BilibiliResolveError(
        code: 'network',
        message: '短链解析失败，请检查链接',
      );
    }
  }

  // 2. Extract BV/AV — prefer passing aid directly for AV numbers
  String? bvid;
  int? aid;
  final bvMatch = RegExp(r'BV[a-zA-Z0-9]{10}').firstMatch(url);
  if (bvMatch != null) {
    bvid = bvMatch.group(0)!;
  } else {
    final avMatch = RegExp(r'av(\d+)', caseSensitive: false).firstMatch(url);
    if (avMatch != null) {
      aid = int.tryParse(avMatch.group(1)!);
    } else {
      final rawNum = RegExp(r'\d+').firstMatch(url);
      if (rawNum != null && !url.contains('http')) {
        aid = int.tryParse(rawNum.group(0)!);
      }
    }
    if (aid == null) {
      throw BilibiliResolveError(
        code: 'parse',
        message: '无法识别 BV/AV 号，请检查链接格式',
      );
    }
  }

  // 3. Extract page parameter
  int page = 1;
  final pageMatch = RegExp(r'[?&]p=(\d+)').firstMatch(url);
  if (pageMatch != null) {
    page = int.tryParse(pageMatch.group(1)!) ?? 1;
    if (page < 1) page = 1;
  }

  // 4. View API — get video metadata (supports both bvid and aid)
  final viewParams = <String, String>{};
  if (bvid != null) {
    viewParams['bvid'] = bvid;
  } else {
    viewParams['aid'] = aid.toString();
  }
  final viewUri = Uri.parse('https://api.bilibili.com/x/web-interface/view')
      .replace(queryParameters: viewParams);
  final viewResult = await _get(viewUri);
  if (viewResult.statusCode != 200 || viewResult.body.isEmpty) {
    throw BilibiliResolveError(
      code: 'network',
      message: '获取视频信息失败（网络错误）',
    );
  }

  Map<String, dynamic> viewData;
  try {
    viewData = json.decode(viewResult.body) as Map<String, dynamic>;
  } catch (_) {
    throw BilibiliResolveError(
      code: 'parse',
      message: '解析视频信息失败',
    );
  }

  if (viewData['code'] != 0) {
    final msg = viewData['message'] as String? ?? '未知错误';
    if (viewData['code'] == -404) {
      throw BilibiliResolveError(code: 'not_found', message: '视频不存在：$msg');
    }
    throw BilibiliResolveError(code: 'parse', message: '获取视频信息失败：$msg');
  }

  final data = viewData['data'] as Map<String, dynamic>;
  // B站 View API 响应始终包含 bvid，即使请求用的是 aid
  bvid = data['bvid'] as String?;
  final title = data['title'] as String? ?? '未知标题';
  final durationSec = (data['duration'] as num?)?.toInt() ?? 0;
  final owner = data['owner'] as Map<String, dynamic>?;
  final ownerName = owner?['name'] as String? ?? '未知UP主';
  final ownerMid = (owner?['mid'] as num?)?.toInt() ?? 0;
  final coverUrl = (data['pic'] as String?) ?? '';
  final stat = data['stat'] as Map<String, dynamic>?;
  final playCount = (stat?['view'] as num?)?.toInt();
  final danmakuCount = (stat?['danmaku'] as num?)?.toInt();

  final pages = data['pages'] as List<dynamic>? ?? [];
  if (pages.isEmpty) {
    throw BilibiliResolveError(code: 'parse', message: '视频无分P数据');
  }

  // Build page info list
  final pageInfos = <BilibiliPageInfo>[];
  for (var i = 0; i < pages.length; i++) {
    final p = pages[i] as Map<String, dynamic>;
    pageInfos.add(BilibiliPageInfo(
      cid: (p['cid'] as num?)?.toInt() ?? 0,
      title: p['part'] as String? ?? 'P${i + 1}',
      page: i + 1,
      duration: (p['duration'] as num?)?.toInt() ?? 0,
    ));
  }

  // Find target page (1-indexed)
  int idx = page - 1;
  if (idx >= pages.length) idx = 0;
  final targetPage = pages[idx] as Map<String, dynamic>;
  final cid = (targetPage['cid'] as num?)?.toInt() ?? 0;
  if (cid == 0) {
    throw BilibiliResolveError(code: 'parse', message: '获取视频 CID 失败');
  }

  // 5. Playurl API — get stream URL
  final playParams = <String, String>{
    'cid': cid.toString(),
    'fnval': '1',
    'platform': 'html5',
    'high_quality': '1',
  };
  if (bvid != null) {
    playParams['bvid'] = bvid;
  } else {
    playParams['aid'] = aid.toString();
  }
  final playUri =
      Uri.parse('https://api.bilibili.com/x/player/playurl').replace(
    queryParameters: playParams,
  );
  final playResult = await _get(playUri);
  if (playResult.statusCode != 200 || playResult.body.isEmpty) {
    throw BilibiliResolveError(
      code: 'network',
      message: '获取播放地址失败（网络错误）',
    );
  }

  Map<String, dynamic> playData;
  try {
    playData = json.decode(playResult.body) as Map<String, dynamic>;
  } catch (_) {
    throw BilibiliResolveError(code: 'parse', message: '解析播放地址失败');
  }

  if (playData['code'] != 0) {
    final msg = playData['message'] as String? ?? '';
    // Try WBI endpoint as fallback hint
    if (msg.contains('wbi') ||
        playData['data'] is Map &&
            (playData['data'] as Map).containsKey('v_voucher')) {
      throw BilibiliResolveError(
        code: 'no_stream',
        message: '该视频需要 WBI 签名，当前版本暂不支持。请尝试其他视频。',
      );
    }
    throw BilibiliResolveError(code: 'no_stream', message: '获取播放地址失败：$msg');
  }

  final playResultData = playData['data'] as Map<String, dynamic>;
  final durl = playResultData['durl'] as List<dynamic>?;
  if (durl == null || durl.isEmpty) {
    throw BilibiliResolveError(
      code: 'no_stream',
      message: '未获取到可播放的流地址',
    );
  }

  final streamUrl = (durl[0] as Map<String, dynamic>)['url'] as String?;
  if (streamUrl == null || streamUrl.isEmpty) {
    throw BilibiliResolveError(
      code: 'no_stream',
      message: '流地址为空',
    );
  }

  final quality =
      (playResultData['quality'] as num?)?.toInt() ?? 0;
  final qualityDesc = _qualityMap[quality] ?? '${quality}P';

  // 6. Construct Song
  final videoId = bvid ?? 'av$aid';
  final song = Song(
    id: 'bili-$videoId-$cid',
    title: title,
    category: '外链',
    artist: Artist(id: 'bili-$ownerMid', name: ownerName),
    duration: Duration(seconds: durationSec),
    isExternal: true,
    assets: [
      MediaAsset(
        id: 'bili-$videoId-video',
        type: MediaAssetType.video,
        uri: Uri.parse(streamUrl),
      ),
    ],
  );

  return BilibiliResolveResult(
    song: song,
    bvid: videoId,
    cid: cid,
    quality: quality,
    qualityDesc: qualityDesc,
    pages: pageInfos,
    selectedPage: page,
    ownerName: ownerName,
    ownerMid: ownerMid,
    coverUrl: coverUrl,
    playCount: playCount,
    danmakuCount: danmakuCount,
  );
}

/// 为指定分P获取可播放的 Song 对象（复用已有的 bvid 和 page info）。
/// 不重新请求 View API，只请求 Playurl API。
Future<Song> resolveBilibiliPage({
  required String bvid,
  required BilibiliPageInfo pageInfo,
  required String ownerName,
  required int ownerMid,
}) async {
  final playUri =
      Uri.parse('https://api.bilibili.com/x/player/playurl').replace(
    queryParameters: {
      'bvid': bvid,
      'cid': pageInfo.cid.toString(),
      'fnval': '1',
      'platform': 'html5',
      'high_quality': '1',
    },
  );
  final playResult = await _get(playUri);
  if (playResult.statusCode != 200 || playResult.body.isEmpty) {
    throw BilibiliResolveError(
      code: 'network',
      message: '获取播放地址失败（网络错误）',
    );
  }

  Map<String, dynamic> playData;
  try {
    playData = json.decode(playResult.body) as Map<String, dynamic>;
  } catch (_) {
    throw BilibiliResolveError(code: 'parse', message: '解析播放地址失败');
  }

  if (playData['code'] != 0) {
    throw BilibiliResolveError(
      code: 'no_stream',
      message: '获取播放地址失败：${playData['message'] ?? ''}',
    );
  }

  final playResultData = playData['data'] as Map<String, dynamic>;
  final durl = playResultData['durl'] as List<dynamic>?;
  if (durl == null || durl.isEmpty) {
    throw BilibiliResolveError(
      code: 'no_stream',
      message: '未获取到可播放的流地址',
    );
  }

  final streamUrl = (durl[0] as Map<String, dynamic>)['url'] as String?;
  if (streamUrl == null || streamUrl.isEmpty) {
    throw BilibiliResolveError(code: 'no_stream', message: '流地址为空');
  }

  return Song(
    id: 'bili-$bvid-${pageInfo.cid}',
    title: pageInfo.title,
    category: '外链',
    artist: Artist(id: 'bili-$ownerMid', name: ownerName),
    duration: Duration(seconds: pageInfo.duration),
    isExternal: true,
    assets: [
      MediaAsset(
        id: 'bili-$bvid-video-${pageInfo.page}',
        type: MediaAssetType.video,
        uri: Uri.parse(streamUrl),
      ),
    ],
  );
}
