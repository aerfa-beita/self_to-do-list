import 'dart:io';

import 'package:flutter/services.dart';

import '../database/database.dart';

class BackupFileService {
  BackupFileService(this._databaseProvider);

  final DatabaseProvider _databaseProvider;
  static const _channel = MethodChannel('todo_list/backup_files');

  Future<String> exportBackup() async {
    if (!Platform.isAndroid) return _databaseProvider.exportAllJson();
    final content = await _databaseProvider.exportAllJsonString();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final saved = await _channel.invokeMethod<bool>('saveJson', {
      'fileName': 'todo_list_backup_$stamp.json',
      'content': content,
    });
    if (saved != true) throw StateError('没有保存备份文件');
    return 'Android 选择的位置';
  }

  Future<String?> pickBackupJson() async {
    if (Platform.isAndroid) {
      return _channel.invokeMethod<String>('pickJson');
    }
    if (!Platform.isWindows) return null;
    const script = r'''
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
$dialog.Multiselect = $false
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  Write-Output $dialog.FileName
}
''';
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-STA',
      '-Command',
      script,
    ]);
    final path = (result.stdout as String).trim();
    if (result.exitCode != 0 || path.isEmpty) return null;
    return File(path).readAsString();
  }
}
