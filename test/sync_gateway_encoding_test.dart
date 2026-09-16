import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todo_list/database/database.dart';
import 'package:todo_list/sync/supabase_sync_gateway.dart';
import 'package:todo_list/sync/sync_config.dart';
import 'package:todo_list/sync/sync_gateway.dart';

void main() {
  // 注意：不用 TestWidgetsFlutterBinding —— 它会劫持 HttpClient 使所有请求返回 400，
  // 本测试需要真实本地 HTTP 服务器验证 body 编码。

  test('push with Chinese payload must reach server as utf8 json', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await DatabaseProvider().openAtPath(inMemoryDatabasePath);
    addTearDown(db.close);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    String? receivedBody;
    server.listen((request) async {
      receivedBody = await utf8.decoder.bind(request).join();
      request.response.statusCode = 200;
      await request.response.close();
    });

    final gateway = SupabaseSyncGateway(
      SyncConfig(
        supabaseUrl: 'http://127.0.0.1:${server.port}',
        anonKey: 'test-key',
        accessToken: '',
        userId: '',
        realtimeEnabled: false,
      ),
      db,
    );

    // 回归：content-type 无 charset 时 dart:io 曾用 latin1 编码 body，
    // 中文 payload 抛 "Contains invalid characters"，请求从未发出。
    await gateway.push([
      CloudChange(
        entityType: 'memo',
        entityId: 'test-id-1',
        operation: 'upsert',
        payload: {'content': '办一张visa卡', '备注': '中文特殊字符：±×÷'},
        revision: 1,
        updatedAt: DateTime.utc(2026, 8, 20),
      ),
    ]);

    expect(receivedBody, isNotNull, reason: '请求应已成功发出');
    final decoded = jsonDecode(receivedBody!) as List<dynamic>;
    final first = decoded.first as Map<String, dynamic>;
    expect(first['payload'], {'content': '办一张visa卡', '备注': '中文特殊字符：±×÷'});
  });
}
