import 'package:flutter/material.dart';

import '../services/app_update_service.dart';

Future<void> showAppUpdateDialog({
  required BuildContext context,
  required AppUpdateService service,
  required AppUpdateCheck update,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _AppUpdateDialog(service: service, update: update),
  );
}

enum _UpdatePhase { ready, downloading, downloaded, error }

class _AppUpdateDialog extends StatefulWidget {
  const _AppUpdateDialog({required this.service, required this.update});

  final AppUpdateService service;
  final AppUpdateCheck update;

  @override
  State<_AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<_AppUpdateDialog> {
  _UpdatePhase _phase = _UpdatePhase.ready;
  UpdateCancelToken? _cancelToken;
  double _progress = 0;
  String? _downloadedPath;
  String? _message;

  Future<void> _download() async {
    final token = UpdateCancelToken();
    setState(() {
      _cancelToken = token;
      _phase = _UpdatePhase.downloading;
      _progress = 0;
      _message = null;
    });
    try {
      final path = await widget.service.downloadAndVerify(
        widget.update,
        cancelToken: token,
        onProgress: (value) {
          if (!mounted || token.isCancelled) return;
          setState(() => _progress = value.clamp(0, 1));
        },
      );
      if (!mounted) return;
      setState(() {
        _downloadedPath = path;
        _phase = _UpdatePhase.downloaded;
        _message = '安装包已通过完整性和身份校验';
      });
    } on UpdateCancelledException {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.ready;
        _message = '下载已取消';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _message = error.toString().replaceFirst('FormatException: ', '');
      });
    } finally {
      _cancelToken = null;
    }
  }

  Future<void> _install() async {
    final path = _downloadedPath;
    if (path == null) return;
    try {
      final result = await widget.service.installDownloaded(path);
      if (!mounted) return;
      switch (result) {
        case UpdateInstallResult.started:
          Navigator.pop(context);
        case UpdateInstallResult.permissionRequired:
          setState(() {
            _message = '请在系统设置中允许“安装未知应用”，返回后再次点击安装';
          });
        case UpdateInstallResult.unsupported:
          setState(() => _message = '当前设备无法启动系统安装界面');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = '启动安装失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final manifest = widget.update.manifest;
    final downloading = _phase == _UpdatePhase.downloading;
    return PopScope(
      canPop: !downloading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && downloading) _cancelToken?.cancel();
      },
      child: AlertDialog(
        icon: Icon(
          widget.update.isRequired
              ? Icons.system_security_update_warning_outlined
              : Icons.system_update_alt_outlined,
        ),
        title: Text(
          widget.update.isRequired
              ? '建议更新到 ${manifest.versionName}'
              : '发现新版本 ${manifest.versionName}',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${AppUpdateService.formatBytes(manifest.sizeBytes)} · '
                  '当前 ${widget.update.installed.versionName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Text('更新内容', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(manifest.changelog),
                if (widget.update.isRequired) ...[
                  const SizedBox(height: 12),
                  Text(
                    '当前版本兼容性较低，建议尽快更新；也可以稍后处理。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (downloading) ...[
                  const SizedBox(height: 18),
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 8),
                  Text('正在下载 ${(100 * _progress).toStringAsFixed(0)}%'),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _message!,
                    style: TextStyle(
                      color: _phase == _UpdatePhase.error
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (downloading)
            TextButton(
              onPressed: () => _cancelToken?.cancel(),
              child: const Text('取消下载'),
            )
          else ...[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('稍后'),
            ),
            FilledButton.icon(
              onPressed: _phase == _UpdatePhase.downloaded
                  ? _install
                  : _download,
              icon: Icon(
                _phase == _UpdatePhase.downloaded
                    ? Icons.install_mobile_outlined
                    : Icons.download_outlined,
              ),
              label: Text(
                _phase == _UpdatePhase.downloaded
                    ? '安装'
                    : _phase == _UpdatePhase.error
                    ? '重新下载'
                    : '下载更新',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
