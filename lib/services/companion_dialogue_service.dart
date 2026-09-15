import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

enum CompanionDialogueMoment {
  idle,
  morning,
  daytime,
  night,
  checkTask,
  celebrate,
  sleepy,
  reminder,
  stash,
}

class CompanionDialogueService {
  CompanionDialogueService({Random? random}) : _random = random ?? Random();

  static const assetPath = 'assets/mascot/companion_dialogues.json';
  static Map<String, List<String>>? _cache;

  final Random _random;
  String? _lastLine;
  DateTime? _lastPickedAt;

  Future<String?> pick({
    required CompanionDialogueMoment moment,
    Duration cooldown = const Duration(seconds: 8),
  }) async {
    final now = DateTime.now();
    if (_lastPickedAt != null && now.difference(_lastPickedAt!) < cooldown) {
      return null;
    }
    final library = await _loadLibrary();
    final contextual = library[moment.name] ?? const <String>[];
    final fallback =
        library[CompanionDialogueMoment.idle.name] ?? const <String>[];
    final candidates = <String>{...contextual, ...fallback}.toList()
      ..remove(_lastLine);
    if (candidates.isEmpty) return _lastLine;
    final selected = candidates[_random.nextInt(candidates.length)];
    _lastLine = selected;
    _lastPickedAt = now;
    return selected;
  }

  Future<Map<String, List<String>>> _loadLibrary() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final source = await rootBundle.loadString(assetPath);
      final decoded = Map<String, dynamic>.from(jsonDecode(source) as Map);
      final parsed = <String, List<String>>{
        for (final entry in decoded.entries)
          entry.key: (entry.value as List<dynamic>)
              .map((line) => line.toString().trim())
              .where((line) => line.isNotEmpty)
              .toList(),
      };
      _cache = parsed;
      return parsed;
    } catch (_) {
      return const {
        'idle': ['我躲在这里，也有认真陪着。'],
        'celebrate': ['完成啦！小花花转一圈！'],
        'reminder': ['时间快到啦，我来轻轻敲门。'],
      };
    }
  }
}
