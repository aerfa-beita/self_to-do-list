import 'dart:convert';

import 'package:flutter/services.dart';

class SyncConfig {
  const SyncConfig({
    required this.supabaseUrl,
    required this.anonKey,
    required this.accessToken,
    required this.userId,
    required this.realtimeEnabled,
  });

  factory SyncConfig.fromEnvironment() {
    return const SyncConfig(
      supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
      anonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
      accessToken: String.fromEnvironment('SUPABASE_ACCESS_TOKEN'),
      userId: String.fromEnvironment('SYNC_USER_ID'),
      realtimeEnabled: bool.fromEnvironment('SYNC_REALTIME'),
    );
  }

  factory SyncConfig.fromJson(
    Map<String, dynamic> json, {
    SyncConfig? environment,
  }) {
    final env = environment ?? SyncConfig.fromEnvironment();
    return SyncConfig(
      supabaseUrl: env.supabaseUrl.isNotEmpty
          ? env.supabaseUrl
          : json['supabaseUrl'] as String? ?? '',
      anonKey: env.anonKey.isNotEmpty
          ? env.anonKey
          : json['publishableKey'] as String? ?? '',
      accessToken: env.accessToken,
      userId: env.userId,
      realtimeEnabled:
          env.realtimeEnabled || (json['realtimeEnabled'] as bool? ?? false),
    );
  }

  static Future<SyncConfig> load({AssetBundle? bundle}) async {
    final environment = SyncConfig.fromEnvironment();
    if (environment.isBackendConfigured) return environment;
    try {
      final source = await (bundle ?? rootBundle).loadString(
        'assets/config/supabase.json',
      );
      return SyncConfig.fromJson(
        Map<String, dynamic>.from(jsonDecode(source) as Map),
        environment: environment,
      );
    } catch (_) {
      return environment;
    }
  }

  final String supabaseUrl;
  final String anonKey;
  final String accessToken;
  final String userId;
  final bool realtimeEnabled;

  bool get isBackendConfigured =>
      supabaseUrl.startsWith('https://') && anonKey.isNotEmpty;

  bool get hasLegacySession => accessToken.isNotEmpty && userId.isNotEmpty;
}
