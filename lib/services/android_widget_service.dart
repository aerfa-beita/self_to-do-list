import 'dart:io';

import 'package:flutter/services.dart';

class AndroidWidgetService {
  const AndroidWidgetService._();

  static const _channel = MethodChannel('todo_list/widgets');

  static Future<void> refresh() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('refresh');
    } on MissingPluginException {
      // Non-Android tests and older installed builds do not expose the bridge.
    } on PlatformException {
      // Widget refresh is best-effort and must not block task persistence.
    }
  }
}
