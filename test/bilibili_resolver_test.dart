import 'package:flutter_test/flutter_test.dart';
import 'package:kirakara_app/services/bilibili_resolver.dart';

void main() {
  group('Bilibili DASH CDN selection', () {
    test('prefers a regular CDN backup over an MCDN base URL', () {
      final selected = selectBilibiliStreamUrl({
        'baseUrl': 'https://edge.mcdn.bilivideo.cn/audio.m4s',
        'backupUrl': [
          'https://upos-sz-mirrorcos.bilivideo.com/audio.m4s',
        ],
      });

      expect(
        selected,
        'https://upos-sz-mirrorcos.bilivideo.com/audio.m4s',
      );
    });

    test('keeps a regular base URL ahead of its backups', () {
      final selected = selectBilibiliStreamUrl({
        'base_url': 'https://cn-gddg-cm-01.bilivideo.com/audio.m4s',
        'backup_url': [
          'https://upos-sz-mirrorcos.bilivideo.com/audio.m4s',
        ],
      });

      expect(
        selected,
        'https://cn-gddg-cm-01.bilivideo.com/audio.m4s',
      );
    });

    test('falls back to MCDN when it is the only candidate', () {
      final selected = selectBilibiliStreamUrl({
        'baseUrl': 'https://edge.mcdn.bilivideo.cn/audio.m4s',
      });

      expect(selected, 'https://edge.mcdn.bilivideo.cn/audio.m4s');
    });
  });
}
