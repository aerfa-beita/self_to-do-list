import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class InstalledAppVersion {
  const InstalledAppVersion({
    required this.versionName,
    required this.versionCode,
  });

  final String versionName;
  final int versionCode;
}

class AppUpdateManifest {
  const AppUpdateManifest({
    required this.versionName,
    required this.versionCode,
    required this.minSupportedVersionCode,
    required this.apkUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.changelog,
    required this.publishedAt,
  });

  final String versionName;
  final int versionCode;
  final int minSupportedVersionCode;
  final Uri apkUrl;
  final String sha256;
  final int sizeBytes;
  final String changelog;
  final DateTime publishedAt;

  factory AppUpdateManifest.fromJson(Map<String, dynamic> json) {
    final versionName = json['versionName'] as String? ?? '';
    final versionCode = (json['versionCode'] as num?)?.toInt() ?? 0;
    final minSupportedVersionCode =
        (json['minSupportedVersionCode'] as num?)?.toInt() ?? 0;
    final apkUrl = Uri.tryParse(json['apkUrl'] as String? ?? '');
    final sha256Value = (json['sha256'] as String? ?? '').toLowerCase();
    final sizeBytes = (json['sizeBytes'] as num?)?.toInt() ?? 0;
    final changelog = json['changelog'] as String? ?? '';
    final publishedAt = DateTime.tryParse(json['publishedAt'] as String? ?? '');
    if (versionName.isEmpty ||
        versionCode <= 0 ||
        minSupportedVersionCode <= 0 ||
        minSupportedVersionCode > versionCode ||
        apkUrl == null ||
        !_isTrustedGithubUri(apkUrl) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256Value) ||
        sizeBytes <= 0 ||
        changelog.trim().isEmpty ||
        publishedAt == null) {
      throw const FormatException('更新清单字段无效');
    }
    return AppUpdateManifest(
      versionName: versionName,
      versionCode: versionCode,
      minSupportedVersionCode: minSupportedVersionCode,
      apkUrl: apkUrl,
      sha256: sha256Value,
      sizeBytes: sizeBytes,
      changelog: changelog.trim(),
      publishedAt: publishedAt.toLocal(),
    );
  }

  static bool _isTrustedGithubUri(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort && uri.port != 443) {
      return false;
    }
    return const {
      'github.com',
      'objects.githubusercontent.com',
      'release-assets.githubusercontent.com',
      'githubusercontent.com',
    }.contains(uri.host.toLowerCase());
  }
}

class AppUpdateCheck {
  const AppUpdateCheck({required this.installed, required this.manifest});

  final InstalledAppVersion installed;
  final AppUpdateManifest manifest;

  bool get isRequired =>
      installed.versionCode < manifest.minSupportedVersionCode;
}

class UpdateCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

enum UpdateInstallResult { started, permissionRequired, unsupported }

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef UpdateManifestLoader = Future<Map<String, dynamic>> Function(Uri uri);
typedef InstalledVersionLoader = Future<InstalledAppVersion> Function();

class AppUpdateService {
  AppUpdateService({
    Uri? manifestUri,
    HttpClient Function()? httpClientFactory,
    Duration? checkTimeout,
    this.manifestLoader,
    this.installedVersionLoader,
  }) : manifestUri = manifestUri ?? Uri.parse(_defaultManifestUrl),
       checkTimeout = checkTimeout ?? const Duration(seconds: 15),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static const _channel = MethodChannel('todo_list/app_update');
  static const _defaultManifestUrl = String.fromEnvironment(
    'UPDATE_MANIFEST_URL',
    defaultValue:
        'https://github.com/aerfa-beita/self_to-do-list/releases/latest/download/update-manifest.json',
  );
  static const _maxManifestBytes = 256 * 1024;

  final Uri manifestUri;
  final Duration checkTimeout;
  final HttpClient Function() _httpClientFactory;
  final UpdateManifestLoader? manifestLoader;
  final InstalledVersionLoader? installedVersionLoader;

  static bool isTrustedDownloadUri(Uri uri) =>
      AppUpdateManifest._isTrustedGithubUri(uri);

  Future<AppUpdateCheck?> checkForUpdate() async {
    if (!isTrustedDownloadUri(manifestUri)) {
      throw const UpdateCheckException('更新清单地址必须使用受信任的 GitHub HTTPS 地址');
    }
    HttpClient? client;
    try {
      final installed = await _loadInstalledVersion();
      final Future<Map<String, dynamic>> manifestFuture;
      if (manifestLoader case final loader?) {
        manifestFuture = loader(manifestUri);
      } else {
        client = _httpClientFactory()..connectionTimeout = checkTimeout;
        manifestFuture = _fetchManifest(client, manifestUri);
      }
      final decoded = await manifestFuture.timeout(
        checkTimeout,
        onTimeout: () {
          client?.close(force: true);
          throw const UpdateCheckException('连接 GitHub 超时，请检查网络后重试');
        },
      );
      final manifest = AppUpdateManifest.fromJson(decoded);
      if (manifest.versionCode <= installed.versionCode) return null;
      return AppUpdateCheck(installed: installed, manifest: manifest);
    } on UpdateCheckException {
      rethrow;
    } on HandshakeException {
      throw const UpdateCheckException('GitHub 安全连接失败，请检查系统时间或网络证书');
    } on SocketException {
      throw const UpdateCheckException('无法连接 GitHub，请检查网络或代理设置');
    } on HttpException catch (error) {
      throw UpdateCheckException(error.message);
    } on FormatException catch (error) {
      throw UpdateCheckException(error.message.toString());
    } catch (_) {
      throw const UpdateCheckException('检查更新失败，请稍后重试');
    } finally {
      client?.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _fetchManifest(
    HttpClient client,
    Uri uri,
  ) async {
    final response = await _get(client, uri);
    if (response.statusCode == HttpStatus.notFound) {
      throw const UpdateCheckException('GitHub Releases 尚未发布更新清单');
    }
    if (response.statusCode != HttpStatus.ok) {
      throw UpdateCheckException('更新服务器返回 HTTP ${response.statusCode}');
    }
    _validateRedirects(response);
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > _maxManifestBytes) {
        throw const UpdateCheckException('更新清单过大');
      }
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const UpdateCheckException('更新清单不是 JSON 对象');
    }
    return decoded;
  }

  Future<String> downloadAndVerify(
    AppUpdateCheck check, {
    required ValueChanged<double> onProgress,
    required UpdateCancelToken cancelToken,
  }) async {
    final path = await _channel.invokeMethod<String>('getUpdateCachePath');
    if (path == null || path.isEmpty) {
      throw StateError('无法创建更新临时文件');
    }
    final file = File(path);
    if (await file.exists()) await file.delete();
    await file.parent.create(recursive: true);
    final client = _httpClientFactory()
      ..connectionTimeout = const Duration(seconds: 20);
    IOSink? sink;
    try {
      final response = await _get(client, check.manifest.apkUrl);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('APK 下载失败：${response.statusCode}');
      }
      _validateRedirects(response);
      if (response.contentLength > 0 &&
          response.contentLength != check.manifest.sizeBytes) {
        throw const FormatException('APK 文件大小与清单不一致');
      }
      sink = file.openWrite();
      var received = 0;
      await for (final chunk in response) {
        if (cancelToken.isCancelled) {
          throw const UpdateCancelledException();
        }
        received += chunk.length;
        if (received > check.manifest.sizeBytes) {
          throw const FormatException('APK 文件超过清单大小');
        }
        sink.add(chunk);
        onProgress(received / check.manifest.sizeBytes);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received != check.manifest.sizeBytes) {
        throw const FormatException('APK 下载不完整');
      }
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString().toLowerCase() != check.manifest.sha256) {
        throw const FormatException('APK SHA-256 校验失败');
      }
      final verification = await _channel
          .invokeMapMethod<String, dynamic>('verifyApk', {
            'path': path,
            'versionCode': check.manifest.versionCode,
            'versionName': check.manifest.versionName,
          });
      if (verification?['valid'] != true) {
        throw FormatException(
          verification?['reason'] as String? ?? 'APK 身份校验失败',
        );
      }
      onProgress(1);
      return path;
    } catch (_) {
      await sink?.close();
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<UpdateInstallResult> installDownloaded(String path) async {
    final result = await _channel.invokeMethod<String>('installApk', {
      'path': path,
    });
    return switch (result) {
      'started' => UpdateInstallResult.started,
      'permission_required' => UpdateInstallResult.permissionRequired,
      _ => UpdateInstallResult.unsupported,
    };
  }

  Future<InstalledAppVersion> _loadInstalledVersion() async {
    if (installedVersionLoader case final loader?) return loader();
    final value = await _channel.invokeMapMethod<String, dynamic>(
      'getInstalledVersion',
    );
    final versionName = value?['versionName'] as String? ?? '';
    final versionCode = (value?['versionCode'] as num?)?.toInt() ?? 0;
    if (versionName.isEmpty || versionCode <= 0) {
      throw StateError('无法读取当前应用版本');
    }
    return InstalledAppVersion(
      versionName: versionName,
      versionCode: versionCode,
    );
  }

  Future<HttpClientResponse> _get(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, 'XiaohuaTodo-Updater');
    request.followRedirects = true;
    request.maxRedirects = 5;
    return request.close();
  }

  void _validateRedirects(HttpClientResponse response) {
    for (final redirect in response.redirects) {
      final location = redirect.location;
      if (!location.isAbsolute || !isTrustedDownloadUri(location)) {
        throw const FormatException('更新下载发生了不受信任的跳转');
      }
    }
  }

  static String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

class UpdateCancelledException implements Exception {
  const UpdateCancelledException();

  @override
  String toString() => '下载已取消';
}
