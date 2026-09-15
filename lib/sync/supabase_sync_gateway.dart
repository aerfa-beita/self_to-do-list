import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sync_config.dart';
import 'sync_gateway.dart';

class SupabaseSyncGateway implements SyncGateway {
  SupabaseSyncGateway(this.config, this._db) {
    _accessToken = config.accessToken;
    _userId = config.userId;
  }

  final SyncConfig config;
  final Database _db;
  String _accessToken = '';
  String _refreshToken = '';
  String _userId = '';
  String _email = '';

  bool get isAuthenticated => _accessToken.isNotEmpty && _userId.isNotEmpty;
  String get signedInEmail => _email;

  Map<String, String> get _headers => {
    'apikey': config.anonKey,
    'authorization': 'Bearer $_accessToken',
    // charset=utf-8 必须显式带上：无 charset 时 dart:io 用 latin1 编码 body，
    // 中文 payload 会抛 "Contains invalid characters"，请求根本发不出去。
    'content-type': 'application/json; charset=utf-8',
  };

  Uri _restUri([String query = '']) {
    final base = config.supabaseUrl.replaceFirst(RegExp(r'/$'), '');
    return Uri.parse('$base/rest/v1/app_records$query');
  }

  @override
  Future<void> push(List<CloudChange> changes) =>
      _push(changes, allowRefresh: true);

  Future<void> _push(
    List<CloudChange> changes, {
    required bool allowRefresh,
  }) async {
    if (changes.isEmpty) return;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.postUrl(
        _restUri('?on_conflict=user_id,entity_type,entity_id'),
      );
      _headers.forEach(request.headers.set);
      request.headers.set('Prefer', 'resolution=merge-duplicates');
      request.write(jsonEncode(changes.map((e) => e.toMap(_userId)).toList()));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode == 401 && allowRefresh) {
        if (await _refreshForRetry()) {
          return _push(changes, allowRefresh: false);
        }
      }
      if (response.statusCode == 401) {
        await _clearSession();
        throw const SyncAuthenticationException('同步登录已过期，请重新登录');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Supabase push ${response.statusCode}: $body');
      }
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<List<CloudChange>> pull({DateTime? changedAfter}) =>
      _pull(changedAfter: changedAfter, allowRefresh: true);

  Future<List<CloudChange>> _pull({
    DateTime? changedAfter,
    required bool allowRefresh,
  }) async {
    final query = StringBuffer(
      '?user_id=eq.${Uri.encodeQueryComponent(_userId)}'
      '&select=entity_type,entity_id,operation,payload,revision,updated_at'
      '&order=updated_at.asc',
    );
    if (changedAfter != null) {
      query.write(
        '&updated_at=gt.${Uri.encodeQueryComponent(changedAfter.toUtc().toIso8601String())}',
      );
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(_restUri(query.toString()));
      _headers.forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode == 401 && allowRefresh) {
        if (await _refreshForRetry()) {
          return _pull(changedAfter: changedAfter, allowRefresh: false);
        }
      }
      if (response.statusCode == 401) {
        await _clearSession();
        throw const SyncAuthenticationException('同步登录已过期，请重新登录');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Supabase pull ${response.statusCode}: $body');
      }
      final decoded = jsonDecode(body) as List<dynamic>;
      return decoded
          .map(
            (item) =>
                CloudChange.fromMap(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
    } finally {
      client.close(force: true);
    }
  }

  @override
  Stream<void> watchRemoteChanges() async* {
    if (!config.realtimeEnabled) return;
    final base = Uri.parse(config.supabaseUrl);
    final uri = base.replace(
      scheme: 'wss',
      path: '/realtime/v1/websocket',
      queryParameters: {'apikey': config.anonKey, 'vsn': '1.0.0'},
    );
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );
    Timer? heartbeat;
    var ref = 1;
    try {
      socket.add(
        jsonEncode({
          'topic': 'realtime:public:app_records',
          'event': 'phx_join',
          'payload': {
            'config': {
              'broadcast': {'self': false},
              'presence': {'key': ''},
              'postgres_changes': [
                {
                  'event': '*',
                  'schema': 'public',
                  'table': 'app_records',
                  'filter': 'user_id=eq.$_userId',
                },
              ],
            },
            'access_token': _accessToken,
          },
          'ref': '${ref++}',
        }),
      );
      heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
        socket.add(
          jsonEncode({
            'topic': 'phoenix',
            'event': 'heartbeat',
            'payload': {},
            'ref': '${ref++}',
          }),
        );
      });
      await for (final raw in socket) {
        final message = jsonDecode(raw as String) as Map<String, dynamic>;
        if (message['event'] == 'postgres_changes') yield null;
      }
    } finally {
      heartbeat?.cancel();
      await socket.close();
    }
  }

  Future<void> restoreSession() async {
    final rows = await _db.query(
      'sync_state',
      where: 'key IN (?, ?, ?, ?)',
      whereArgs: ['access_token', 'refresh_token', 'user_id', 'email'],
    );
    final values = {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
    _accessToken = values['access_token'] ?? _accessToken;
    _refreshToken = values['refresh_token'] ?? '';
    _userId = values['user_id'] ?? _userId;
    _email = values['email'] ?? '';
    if (_refreshToken.isNotEmpty) {
      try {
        await _refreshSession();
      } catch (_) {
        // 离线启动继续使用现有会话；修改仍留在本地同步队列。
      }
    }
  }

  Future<void> signIn(String email, String password) =>
      _authenticate(email, password, signUp: false);

  Future<void> signUp(String email, String password) =>
      _authenticate(email, password, signUp: true);

  Future<void> _authenticate(
    String email,
    String password, {
    required bool signUp,
  }) async {
    final base = config.supabaseUrl.replaceFirst(RegExp(r'/$'), '');
    final uri = Uri.parse(
      signUp
          ? '$base/auth/v1/signup'
          : '$base/auth/v1/token?grant_type=password',
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.postUrl(uri);
      request.headers.set('apikey', config.anonKey);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'email': email.trim(), 'password': password}));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final decoded = jsonDecode(body);
        final message = decoded is Map
            ? decoded['msg'] ??
                  decoded['message'] ??
                  decoded['error_description']
            : body;
        throw StateError('$message');
      }
      final decoded = Map<String, dynamic>.from(jsonDecode(body) as Map);
      final user = decoded['user'] as Map?;
      final accessToken = decoded['access_token'] as String?;
      if (accessToken == null || user == null) {
        throw StateError(signUp ? '注册成功，请完成邮箱验证后登录' : '登录响应缺少会话');
      }
      _accessToken = accessToken;
      _refreshToken = decoded['refresh_token'] as String? ?? '';
      _userId = user['id'] as String;
      _email = email.trim();
      await _persistSession();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _refreshSession() async {
    final base = config.supabaseUrl.replaceFirst(RegExp(r'/$'), '');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.postUrl(
        Uri.parse('$base/auth/v1/token?grant_type=refresh_token'),
      );
      request.headers.set('apikey', config.anonKey);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'refresh_token': _refreshToken}));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('会话刷新失败');
      }
      final decoded = Map<String, dynamic>.from(jsonDecode(body) as Map);
      _accessToken = decoded['access_token'] as String;
      _refreshToken = decoded['refresh_token'] as String? ?? _refreshToken;
      final user = decoded['user'] as Map?;
      if (user != null) _userId = user['id'] as String;
      await _persistSession();
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _refreshForRetry() async {
    if (_refreshToken.isEmpty) return false;
    try {
      await _refreshSession();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persistSession() async {
    final values = {
      'access_token': _accessToken,
      'refresh_token': _refreshToken,
      'user_id': _userId,
      'email': _email,
    };
    for (final entry in values.entries) {
      await _db.insert('sync_state', {
        'key': entry.key,
        'value': entry.value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> signOut() async {
    await _clearSession();
  }

  Future<void> _clearSession() async {
    _accessToken = '';
    _refreshToken = '';
    _userId = '';
    _email = '';
    await _db.delete(
      'sync_state',
      where: 'key IN (?, ?, ?, ?)',
      whereArgs: ['access_token', 'refresh_token', 'user_id', 'email'],
    );
  }
}
