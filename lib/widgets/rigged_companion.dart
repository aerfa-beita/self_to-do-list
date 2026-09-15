import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/companion_rig_service.dart';

class CompanionPartPose {
  const CompanionPartPose({this.rotation = 0, this.offset = Offset.zero});

  final double rotation;
  final Offset offset;
}

class CompanionMotion {
  const CompanionMotion({
    this.bodyOffset = Offset.zero,
    this.bodyRotation = 0,
    this.bodyScale = 1,
    this.parts = const {},
    this.gripping = false,
  });

  final Offset bodyOffset;
  final double bodyRotation;
  final double bodyScale;
  final Map<String, CompanionPartPose> parts;
  final bool gripping;

  factory CompanionMotion.walk(double progress, {required bool movingLeft}) {
    final wave = math.sin(progress * math.pi * 2);
    final liftLeft = math.max(0.0, wave);
    final liftRight = math.max(0.0, -wave);
    final plantedCorrection = wave >= 0 ? -wave * 2.2 : -wave * 2.2;
    return CompanionMotion(
      bodyOffset: Offset(plantedCorrection, -1.8 * wave.abs()),
      bodyRotation: wave * .012 * (movingLeft ? -1 : 1),
      parts: {
        'left_thigh': CompanionPartPose(rotation: wave * .19),
        'right_thigh': CompanionPartPose(rotation: -wave * .19),
        'left_shin_foot': CompanionPartPose(
          rotation: -wave * .12 + liftLeft * .2,
          offset: Offset(0, -liftLeft * 4.5),
        ),
        'right_shin_foot': CompanionPartPose(
          rotation: wave * .12 - liftRight * .2,
          offset: Offset(0, -liftRight * 4.5),
        ),
        'left_upper_arm': CompanionPartPose(rotation: -wave * .13),
        'right_upper_arm': CompanionPartPose(rotation: wave * .13),
        'left_forearm_hand_open': CompanionPartPose(rotation: -wave * .08),
        'right_forearm_hand_open': CompanionPartPose(rotation: wave * .08),
        'head_hair_glasses': CompanionPartPose(rotation: -wave * .008),
        'earring_pendant': CompanionPartPose(rotation: wave * .06),
      },
    );
  }

  factory CompanionMotion.reach(double progress, {bool gripping = false}) {
    final eased = Curves.easeInOut.transform(progress.clamp(0, 1));
    return CompanionMotion(
      bodyOffset: Offset(0, eased * 4),
      bodyRotation: -.06 * eased,
      bodyScale: 1 - eased * .02,
      gripping: gripping,
      parts: {
        'left_upper_arm': CompanionPartPose(rotation: .23 * eased),
        'right_upper_arm': CompanionPartPose(rotation: -.23 * eased),
        'left_forearm_hand_open': CompanionPartPose(rotation: .16 * eased),
        'right_forearm_hand_open': CompanionPartPose(rotation: -.16 * eased),
        'left_forearm_hand_grip': CompanionPartPose(rotation: .16 * eased),
        'right_forearm_hand_grip': CompanionPartPose(rotation: -.16 * eased),
        'left_thigh': CompanionPartPose(rotation: -.12 * eased),
        'right_thigh': CompanionPartPose(rotation: .12 * eased),
      },
    );
  }

  factory CompanionMotion.carry(double progress, {required bool movingLeft}) {
    final gait = CompanionMotion.walk(progress, movingLeft: movingLeft);
    final wave = math.sin(progress * math.pi * 2);
    return CompanionMotion(
      bodyOffset: gait.bodyOffset,
      bodyRotation: gait.bodyRotation,
      parts: {
        ...gait.parts,
        'left_upper_arm': const CompanionPartPose(rotation: .14),
        'right_upper_arm': const CompanionPartPose(rotation: -.14),
        'left_forearm_hand_grip': CompanionPartPose(rotation: .12 + wave * .01),
        'right_forearm_hand_grip': CompanionPartPose(
          rotation: -.12 - wave * .01,
        ),
      },
      gripping: true,
    );
  }
}

class RiggedCompanion extends StatelessWidget {
  const RiggedCompanion({
    super.key,
    required this.size,
    required this.direction,
    required this.motion,
    this.taskCard,
    this.fallback,
  });

  final double size;
  final CompanionDirection direction;
  final CompanionMotion motion;
  final Widget? taskCard;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: FutureBuilder<CompanionRig>(
        future: CompanionRigService.instance.load(),
        builder: (context, snapshot) {
          final rig = snapshot.data;
          if (rig == null) return fallback ?? const SizedBox.shrink();
          return RepaintBoundary(
            child: Transform.translate(
              offset: motion.bodyOffset * (size / rig.width),
              child: Transform.rotate(
                angle: motion.bodyRotation,
                child: Transform.scale(
                  scale: motion.bodyScale,
                  child: _RigCanvas(
                    rig: rig,
                    direction: direction,
                    motion: motion,
                    taskCard: taskCard,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RigCanvas extends StatelessWidget {
  const _RigCanvas({
    required this.rig,
    required this.direction,
    required this.motion,
    required this.taskCard,
  });

  final CompanionRig rig;
  final CompanionDirection direction;
  final CompanionMotion motion;
  final Widget? taskCard;

  @override
  Widget build(BuildContext context) {
    final directionRig = rig.direction(direction);
    final children = <Widget>[];
    var taskInserted = false;
    for (final part in directionRig.parts) {
      final isGrip = part.name.endsWith('_grip');
      final isOpen = part.name.endsWith('_open');
      if ((isGrip && !motion.gripping) || (isOpen && motion.gripping)) continue;
      if (!part.defaultVisible && !isGrip) continue;
      if (!taskInserted && taskCard != null && part.zIndex >= 23) {
        children.add(_taskAt(directionRig.taskCarryAnchor, taskCard!));
        taskInserted = true;
      }
      children.add(_part(part));
    }
    if (!taskInserted && taskCard != null) {
      children.add(_taskAt(directionRig.taskCarryAnchor, taskCard!));
    }
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: rig.width,
        height: rig.height,
        child: Stack(clipBehavior: Clip.none, children: children),
      ),
    );
  }

  Widget _part(CompanionRigPart part) {
    final pose = motion.parts[part.name] ?? const CompanionPartPose();
    final alignment = Alignment(
      ((part.pivotX - part.x) / part.width) * 2 - 1,
      ((part.pivotY - part.y) / part.height) * 2 - 1,
    );
    return Positioned(
      left: part.x + pose.offset.dx,
      top: part.y + pose.offset.dy,
      width: part.width,
      height: part.height,
      child: Transform.rotate(
        key: ValueKey('rig-part-${direction.name}-${part.name}'),
        angle: pose.rotation,
        alignment: alignment,
        child: Image.asset(
          part.assetPath,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
        ),
      ),
    );
  }

  Widget _taskAt(CompanionPoint anchor, Widget child) => Positioned(
    left: anchor.x - 58,
    top: anchor.y - 24,
    width: 116,
    height: 48,
    child: child,
  );
}
