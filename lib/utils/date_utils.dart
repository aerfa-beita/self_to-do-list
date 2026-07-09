import 'package:flutter/material.dart';

/// 根据分类名称生成颜色（固定调色板、确定性 hash）
Color categoryColor(String name) {
  final hash = name.codeUnits.fold<int>(0, (s, c) => s + c) % 12;
  const palette = [
    Colors.blueGrey, Colors.blue, Colors.green, Colors.orange,
    Colors.red, Colors.purple, Colors.teal, Colors.indigo,
    Colors.amber, Colors.cyan, Colors.pink, Colors.brown,
  ];
  return palette[hash];
}

/// 日期格式化——项目中统一使用
String fmtDate(DateTime date) {
  final now = DateTime.now();
  final diff = date.difference(DateTime(now.year, now.month, now.day)).inDays;
  final base = diff == 0 ? '今天' : diff == 1 ? '明天' : diff == -1 ? '昨天' : '${date.month}/${date.day}';
  return base;
}

/// 日期+时间
String fmtDateTime(DateTime? date, DateTime? time) {
  if (date == null) return '';
  final d = fmtDate(date);
  if (time == null) return d;
  return '$d ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

String fmtRelativeTime(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
