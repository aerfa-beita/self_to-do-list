import 'dart:math';

/// 生成不依赖本机自增主键的稳定 ID，供 Windows / Android 同步使用。
class SyncId {
  SyncId._();

  static final Random _random = Random.secure();

  static String generate() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// 为没有 sync_id 的旧版 JSON 生成可重复的 UUID。
  /// 同一个备份重复导入时会命中同一条记录，不会不断产生副本。
  static String fromLegacy(String value) {
    int fnv32(int seed) {
      var hash = (0x811C9DC5 ^ seed) & 0xFFFFFFFF;
      for (final unit in value.codeUnits) {
        hash ^= unit;
        hash = (hash * 0x01000193) & 0xFFFFFFFF;
      }
      return hash;
    }

    final bytes = <int>[];
    for (final seed in const [0x13579BDF, 0x2468ACE0, 0x10203040, 0x55667788]) {
      final hash = fnv32(seed);
      bytes.addAll([
        (hash >> 24) & 0xFF,
        (hash >> 16) & 0xFF,
        (hash >> 8) & 0xFF,
        hash & 0xFF,
      ]);
    }
    bytes[6] = (bytes[6] & 0x0F) | 0x50;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
