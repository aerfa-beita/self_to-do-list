import 'package:flutter_test/flutter_test.dart';
import 'package:todo_list/services/companion_rig_service.dart';

void main() {
  testWidgets('2.5D rig has independent directions and all 15 parts', (
    tester,
  ) async {
    late CompanionRig rig;
    await tester.runAsync(() async {
      rig = await CompanionRigService.instance.load();
    });

    for (final direction in CompanionDirection.values) {
      expect(rig.direction(direction).parts, hasLength(15));
    }
    final leftHead = rig
        .direction(CompanionDirection.left)
        .parts
        .firstWhere((part) => part.name == 'head_hair_glasses');
    final rightHead = rig
        .direction(CompanionDirection.right)
        .parts
        .firstWhere((part) => part.name == 'head_hair_glasses');
    expect(leftHead.assetPath, isNot(rightHead.assetPath));
    expect(
      rig
          .direction(CompanionDirection.front)
          .parts
          .where((part) => part.name.contains('forearm_hand')),
      hasLength(4),
    );
  });
}
