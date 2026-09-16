import '../utils/sync_id.dart';

class Task {
  static const String normalMode = 'normal';
  static const String legacyFlowMode = 'flow';
  static const String planNowMode = 'plan_now';
  static const String planNextMode = 'plan_next';
  static const String planLaterMode = 'plan_later';
  static const String flowMode = planNowMode;
  static const String actionScopeInbox = 'inbox';
  static const String actionScopeStage = 'stage';
  static const String actionScopeWeek = 'week';
  static const List<String> actionScopes = [
    actionScopeInbox,
    actionScopeStage,
    actionScopeWeek,
  ];
  static const List<String> arrangementModes = [
    planNowMode,
    planNextMode,
    planLaterMode,
  ];

  final int? id;
  final String title;
  final String note;
  final String category;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? completedScope;
  final DateTime? deletedAt;
  final String? deletedScope;
  final DateTime? dueDate;
  final DateTime? reminderTime;
  final String? repeatType; // null=不重复, 'daily', 'weekly', 'monthly'
  final int sortOrder;
  final int weekSortOrder;
  final int effortPoints;
  final DateTime? companionStashedAt;
  final String taskMode;
  final String syncId;
  final DateTime updatedAt;
  final int revision;

  Task({
    this.id,
    required this.title,
    this.note = '',
    this.category = '默认',
    DateTime? createdAt,
    this.completedAt,
    String? completedScope,
    this.deletedAt,
    String? deletedScope,
    this.dueDate,
    this.reminderTime,
    this.repeatType,
    this.sortOrder = 0,
    int? weekSortOrder,
    this.effortPoints = 2,
    this.companionStashedAt,
    this.taskMode = normalMode,
    String? syncId,
    DateTime? updatedAt,
    this.revision = 1,
  }) : completedScope = normalizeActionScope(completedScope),
       deletedScope = normalizeActionScope(deletedScope),
       weekSortOrder = weekSortOrder ?? sortOrder,
       syncId = syncId ?? SyncId.generate(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  bool get isDeleted => deletedAt != null;
  bool get isCompleted => completedAt != null;
  bool get isArranged => taskMode != normalMode;
  bool get isScheduled => isArranged || dueDate != null;
  bool get isFlow => isArranged;

  int get arrangementStage => switch (taskMode) {
    planNextMode => 1,
    planLaterMode => 2,
    _ => 0,
  };

  String get arrangementLabel => arrangementLabelForMode(taskMode);

  static String arrangementLabelForMode(String? mode) =>
      switch (normalizeMode(mode)) {
        planNextMode => '接下来',
        planLaterMode => '稍后',
        _ => '现在',
      };

  static String normalizeMode(String? value) => switch (value) {
    planNextMode => planNextMode,
    planLaterMode => planLaterMode,
    planNowMode || legacyFlowMode => planNowMode,
    _ => normalMode,
  };

  static String? normalizeActionScope(String? value) =>
      actionScopes.contains(value) ? value : null;

  static String inferActionScope({String? taskMode, Object? dueDate}) {
    if (normalizeMode(taskMode) != normalMode) return actionScopeStage;
    if (dueDate != null) return actionScopeWeek;
    return actionScopeInbox;
  }

  String get inferredActionScope =>
      inferActionScope(taskMode: taskMode, dueDate: dueDate);

  /// 只看日期不看时间：今天不算过期
  bool get isOverdue {
    if (dueDate == null || isCompleted) return false;
    final dueDay = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    return dueDay.isBefore(today);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'note': note,
      'category': category,
      'created_at': createdAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'completed_scope': completedScope,
      'deleted_at': deletedAt?.toIso8601String(),
      'deleted_scope': deletedScope,
      'due_date': dueDate?.toIso8601String(),
      'reminder_time': reminderTime?.toIso8601String(),
      'repeat_type': repeatType,
      'sort_order': sortOrder,
      'week_sort_order': weekSortOrder,
      'effort_points': effortPoints,
      'companion_stashed_at': companionStashedAt?.toIso8601String(),
      'task_mode': taskMode,
      'sync_id': syncId,
      'updated_at': updatedAt.toIso8601String(),
      'revision': revision,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'],
      title: map['title'],
      note: map['note'] ?? '',
      category: map['category'] ?? '默认',
      createdAt: DateTime.parse(map['created_at']),
      completedAt: map['completed_at'] != null
          ? DateTime.parse(map['completed_at'])
          : null,
      completedScope: map['completed_at'] != null
          ? normalizeActionScope(map['completed_scope'] as String?) ??
                inferActionScope(
                  taskMode: map['task_mode'] as String?,
                  dueDate: map['due_date'],
                )
          : null,
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'])
          : null,
      deletedScope: map['deleted_at'] != null
          ? normalizeActionScope(map['deleted_scope'] as String?) ??
                inferActionScope(
                  taskMode: map['task_mode'] as String?,
                  dueDate: map['due_date'],
                )
          : null,
      dueDate: map['due_date'] != null ? DateTime.parse(map['due_date']) : null,
      reminderTime: map['reminder_time'] != null
          ? DateTime.parse(map['reminder_time'])
          : null,
      repeatType: map['repeat_type'] as String?,
      sortOrder: map['sort_order'] ?? 0,
      weekSortOrder: map['week_sort_order'] ?? map['sort_order'] ?? 0,
      effortPoints: map['effort_points'] ?? 2,
      companionStashedAt: map['companion_stashed_at'] != null
          ? DateTime.parse(map['companion_stashed_at'])
          : null,
      taskMode: normalizeMode(map['task_mode'] as String?),
      syncId: map['sync_id'] as String?,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : DateTime.parse(map['created_at']),
      revision: map['revision'] ?? 1,
    );
  }

  Task copyWith({
    int? id,
    String? title,
    String? note,
    String? category,
    DateTime? createdAt,
    DateTime? completedAt,
    String? completedScope,
    DateTime? deletedAt,
    String? deletedScope,
    DateTime? dueDate,
    DateTime? reminderTime,
    int? sortOrder,
    int? weekSortOrder,
    int? effortPoints,
    DateTime? companionStashedAt,
    String? taskMode,
    String? syncId,
    DateTime? updatedAt,
    int? revision,
    bool clearCompletedAt = false,
    bool clearCompletedScope = false,
    bool clearDeletedAt = false,
    bool clearDeletedScope = false,
    String? repeatType,
    bool clearRepeatType = false,
    bool clearDueDate = false,
    bool clearReminderTime = false,
    bool clearCompanionStashedAt = false,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      note: note ?? this.note,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      completedScope: clearCompletedScope
          ? null
          : (completedScope ?? this.completedScope),
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      deletedScope: clearDeletedScope
          ? null
          : (deletedScope ?? this.deletedScope),
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      reminderTime: clearReminderTime
          ? null
          : (reminderTime ?? this.reminderTime),
      repeatType: clearRepeatType ? null : (repeatType ?? this.repeatType),
      sortOrder: sortOrder ?? this.sortOrder,
      weekSortOrder: weekSortOrder ?? this.weekSortOrder,
      effortPoints: effortPoints ?? this.effortPoints,
      companionStashedAt: clearCompanionStashedAt
          ? null
          : (companionStashedAt ?? this.companionStashedAt),
      taskMode: taskMode ?? this.taskMode,
      syncId: syncId ?? this.syncId,
      updatedAt: updatedAt ?? DateTime.now(),
      revision: revision ?? (this.revision + 1),
    );
  }
}
