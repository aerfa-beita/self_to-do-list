import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_list/sync/sync_config.dart';

class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.source);

  final String source;

  @override
  Future<ByteData> load(String key) async {
    final bytes = Uint8List.fromList(utf8.encode(source));
    return ByteData.sublistView(bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local public config enables the backend without build flags', () async {
    final config = await SyncConfig.load(
      bundle: _MemoryAssetBundle(
        jsonEncode({
          'supabaseUrl': 'https://example.supabase.co',
          'publishableKey': 'sb_publishable_test_value',
          'realtimeEnabled': true,
        }),
      ),
    );

    expect(config.isBackendConfigured, isTrue);
    expect(config.supabaseUrl, 'https://example.supabase.co');
    expect(config.anonKey, 'sb_publishable_test_value');
    expect(config.realtimeEnabled, isTrue);
  });
}
