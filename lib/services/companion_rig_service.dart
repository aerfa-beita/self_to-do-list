import 'dart:convert';

import 'package:flutter/services.dart';

enum CompanionDirection { front, left, right }

class CompanionPoint {
  const CompanionPoint(this.x, this.y);

  final double x;
  final double y;

  factory CompanionPoint.fromJson(Map<String, dynamic> json) => CompanionPoint(
    (json['x'] as num).toDouble(),
    (json['y'] as num).toDouble(),
  );
}

class CompanionRigPart {
  const CompanionRigPart({
    required this.name,
    required this.assetPath,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.pivotX,
    required this.pivotY,
    required this.zIndex,
    required this.defaultVisible,
  });

  final String name;
  final String assetPath;
  final double x;
  final double y;
  final double width;
  final double height;
  final double pivotX;
  final double pivotY;
  final int zIndex;
  final bool defaultVisible;

  factory CompanionRigPart.fromJson(Map<String, dynamic> json) {
    final sourcePath = json['fileName'] as String;
    return CompanionRigPart(
      name: json['name'] as String,
      assetPath: 'assets/mascot/2_5d/${sourcePath.replaceFirst('assets/', '')}',
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      pivotX: (json['rotationPivotX'] as num).toDouble(),
      pivotY: (json['rotationPivotY'] as num).toDouble(),
      zIndex: json['zIndex'] as int,
      defaultVisible: json['defaultVisible'] as bool,
    );
  }
}

class CompanionDirectionRig {
  CompanionDirectionRig({
    required List<CompanionRigPart> parts,
    required this.leftHandGripAnchor,
    required this.rightHandGripAnchor,
    required this.leftFootContactAnchor,
    required this.rightFootContactAnchor,
    required this.taskCarryAnchor,
  }) : parts = List.unmodifiable(
         parts..sort((a, b) => a.zIndex.compareTo(b.zIndex)),
       );

  final List<CompanionRigPart> parts;
  final CompanionPoint leftHandGripAnchor;
  final CompanionPoint rightHandGripAnchor;
  final CompanionPoint leftFootContactAnchor;
  final CompanionPoint rightFootContactAnchor;
  final CompanionPoint taskCarryAnchor;

  factory CompanionDirectionRig.fromJson(
    Map<String, dynamic> json,
  ) => CompanionDirectionRig(
    parts: (json['parts'] as List<dynamic>)
        .map(
          (part) =>
              CompanionRigPart.fromJson(Map<String, dynamic>.from(part as Map)),
        )
        .toList(),
    leftHandGripAnchor: CompanionPoint.fromJson(
      Map<String, dynamic>.from(json['leftHandGripAnchor'] as Map),
    ),
    rightHandGripAnchor: CompanionPoint.fromJson(
      Map<String, dynamic>.from(json['rightHandGripAnchor'] as Map),
    ),
    leftFootContactAnchor: CompanionPoint.fromJson(
      Map<String, dynamic>.from(json['leftFootContactAnchor'] as Map),
    ),
    rightFootContactAnchor: CompanionPoint.fromJson(
      Map<String, dynamic>.from(json['rightFootContactAnchor'] as Map),
    ),
    taskCarryAnchor: CompanionPoint.fromJson(
      Map<String, dynamic>.from(json['taskCarryAnchor'] as Map),
    ),
  );
}

class CompanionRig {
  const CompanionRig({
    required this.width,
    required this.height,
    required this.directions,
  });

  final double width;
  final double height;
  final Map<CompanionDirection, CompanionDirectionRig> directions;

  CompanionDirectionRig direction(CompanionDirection direction) =>
      directions[direction]!;

  factory CompanionRig.fromJson(Map<String, dynamic> json) {
    final canvas = Map<String, dynamic>.from(json['canvas'] as Map);
    final directions = Map<String, dynamic>.from(json['directions'] as Map);
    return CompanionRig(
      width: (canvas['width'] as num).toDouble(),
      height: (canvas['height'] as num).toDouble(),
      directions: {
        for (final direction in CompanionDirection.values)
          direction: CompanionDirectionRig.fromJson(
            Map<String, dynamic>.from(directions[direction.name] as Map),
          ),
      },
    );
  }
}

class CompanionRigService {
  CompanionRigService._();

  static final CompanionRigService instance = CompanionRigService._();
  Future<CompanionRig>? _cachedRig;

  Future<CompanionRig> load() => _cachedRig ??= _load();

  Future<CompanionRig> _load() async {
    final source = await rootBundle.loadString(
      'assets/mascot/2_5d/mascot_rig.json',
    );
    return CompanionRig.fromJson(
      Map<String, dynamic>.from(jsonDecode(source) as Map),
    );
  }
}
