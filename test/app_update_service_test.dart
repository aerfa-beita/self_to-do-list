import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo_list/services/app_update_service.dart';

void main() {
  group('AppUpdateManifest', () {
    test('parses a complete GitHub release manifest', () {
      final manifest = AppUpdateManifest.fromJson({
        'versionName': '1.3.0',
        'versionCode': 6,
        'minSupportedVersionCode': 5,
        'apkUrl':
            'https://github.com/aerfa-beita/self_to-do-list/releases/download/v1.3.0/xiaohua-todo-1.3.0.apk',
        'sha256': 'a' * 64,
        'sizeBytes': 1024,
        'changelog': '修复本周任务并加入应用内更新',
        'publishedAt': '2026-09-16T08:00:00Z',
      });

      expect(manifest.versionCode, 6);
      expect(manifest.minSupportedVersionCode, 5);
      expect(manifest.apkUrl.scheme, 'https');
      expect(manifest.changelog, '修复本周任务并加入应用内更新');
      expect(
        AppUpdateService.isTrustedDownloadUri(
          Uri.parse('https://release-assets.githubusercontent.com/file.apk'),
        ),
        isTrue,
      );
    });

    test('rejects non-HTTPS and non-GitHub APK sources', () {
      Map<String, Object> data(String url) => {
        'versionName': '1.3.0',
        'versionCode': 6,
        'minSupportedVersionCode': 5,
        'apkUrl': url,
        'sha256': 'b' * 64,
        'sizeBytes': 2048,
        'changelog': '更新',
        'publishedAt': '2026-09-16T08:00:00Z',
      };

      expect(
        () => AppUpdateManifest.fromJson(data('http://github.com/file.apk')),
        throwsFormatException,
      );
      expect(
        () => AppUpdateManifest.fromJson(data('https://example.com/file.apk')),
        throwsFormatException,
      );
      expect(
        () =>
            AppUpdateManifest.fromJson(data('https://github.com:444/file.apk')),
        throwsFormatException,
      );
    });

    test('rejects malformed integrity and version fields', () {
      final data = {
        'versionName': '1.3.0',
        'versionCode': 5,
        'minSupportedVersionCode': 6,
        'apkUrl': 'https://github.com/example/file.apk',
        'sha256': 'not-a-sha',
        'sizeBytes': 0,
        'changelog': '',
        'publishedAt': 'bad-date',
      };

      expect(() => AppUpdateManifest.fromJson(data), throwsFormatException);
    });
  });

  test('required update uses version codes', () {
    final check = AppUpdateCheck(
      installed: const InstalledAppVersion(
        versionName: '1.2.2',
        versionCode: 5,
      ),
      manifest: AppUpdateManifest.fromJson({
        'versionName': '2.0.0',
        'versionCode': 10,
        'minSupportedVersionCode': 6,
        'apkUrl': 'https://github.com/example/file.apk',
        'sha256': 'c' * 64,
        'sizeBytes': 4096,
        'changelog': '重大更新',
        'publishedAt': '2026-09-16T08:00:00Z',
      }),
    );

    expect(check.isRequired, isTrue);
  });

  test('formats download sizes for the update dialog', () {
    expect(AppUpdateService.formatBytes(1024), '1 KB');
    expect(AppUpdateService.formatBytes(1572864), '1.5 MB');
  });

  group('AppUpdateService check', () {
    final manifestUri = Uri.parse(
      'https://github.com/example/releases/latest/download/update-manifest.json',
    );
    const installed = InstalledAppVersion(versionName: '1.2.2', versionCode: 5);

    test('applies a total timeout to manifest loading', () async {
      final service = AppUpdateService(
        manifestUri: manifestUri,
        checkTimeout: const Duration(milliseconds: 10),
        installedVersionLoader: () async => installed,
        manifestLoader: (_) => Completer<Map<String, dynamic>>().future,
      );

      await expectLater(
        service.checkForUpdate(),
        throwsA(
          isA<UpdateCheckException>().having(
            (error) => error.message,
            'message',
            contains('超时'),
          ),
        ),
      );
    });

    test('turns network failures into an actionable message', () async {
      final service = AppUpdateService(
        manifestUri: manifestUri,
        installedVersionLoader: () async => installed,
        manifestLoader: (_) => throw const SocketException('offline'),
      );

      await expectLater(
        service.checkForUpdate(),
        throwsA(
          isA<UpdateCheckException>().having(
            (error) => error.message,
            'message',
            contains('网络或代理'),
          ),
        ),
      );
    });

    test('returns a newer release from an injected manifest', () async {
      final service = AppUpdateService(
        manifestUri: manifestUri,
        installedVersionLoader: () async => installed,
        manifestLoader: (_) async => {
          'versionName': '1.3.0',
          'versionCode': 6,
          'minSupportedVersionCode': 5,
          'apkUrl': 'https://github.com/example/file.apk',
          'sha256': 'e' * 64,
          'sizeBytes': 4096,
          'changelog': '更新检查修复',
          'publishedAt': '2026-09-17T08:00:00Z',
        },
      );

      final update = await service.checkForUpdate();

      expect(update?.manifest.versionCode, 6);
      expect(update?.isRequired, isFalse);
    });
  });
}
