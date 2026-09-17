import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_list/services/app_update_service.dart';
import 'package:todo_list/widgets/app_update_dialog.dart';

void main() {
  testWidgets('update dialog fits a 320dp Android screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final update = AppUpdateCheck(
      installed: const InstalledAppVersion(
        versionName: '1.2.2',
        versionCode: 5,
      ),
      manifest: AppUpdateManifest.fromJson({
        'versionName': '1.3.0',
        'versionCode': 6,
        'minSupportedVersionCode': 5,
        'apkUrl': 'https://github.com/example/file.apk',
        'sha256': 'd' * 64,
        'sizeBytes': 1572864,
        'changelog': '修复本周历史任务显示\n加入应用内更新',
        'publishedAt': '2026-09-16T08:00:00Z',
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showAppUpdateDialog(
                  context: context,
                  service: AppUpdateService(),
                  update: update,
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本 1.3.0'), findsOneWidget);
    expect(find.text('1.5 MB · 当前 1.2.2'), findsOneWidget);
    expect(find.text('下载更新'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a minimum-version warning can still be postponed', (
    tester,
  ) async {
    final update = AppUpdateCheck(
      installed: const InstalledAppVersion(
        versionName: '1.2.2',
        versionCode: 5,
      ),
      manifest: AppUpdateManifest.fromJson({
        'versionName': '2.0.0',
        'versionCode': 10,
        'minSupportedVersionCode': 6,
        'apkUrl': 'https://github.com/example/file.apk',
        'sha256': 'f' * 64,
        'sizeBytes': 1572864,
        'changelog': '重要兼容更新',
        'publishedAt': '2026-09-17T08:00:00Z',
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showAppUpdateDialog(
                context: context,
                service: AppUpdateService(),
                update: update,
              ),
              child: const Text('打开强更新提示'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开强更新提示'));
    await tester.pumpAndSettle();
    expect(find.text('建议更新到 2.0.0'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);

    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(find.text('建议更新到 2.0.0'), findsNothing);
  });
}
