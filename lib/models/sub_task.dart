class SubTask {
  final int? id;
  final int taskId;
  final int? parentId; // null = top-level, otherwise points to parent SubTask.id
  final int level;     // 0 = top-level, max 4 (5 levels total)
  final String title;
  final bool isDone;
  final int sortOrder;
  final DateTime? dueDate;
  final DateTime? reminderTime;
  final String? repeatType;
  final DateTime? deletedAt;

  SubTask({
    this.id,
    required this.taskId,
    this.parentId,
    this.level = 0,
    required this.title,
    this.isDone = false,
    this.sortOrder = 0,
    this.dueDate,
    this.reminderTime,
    this.repeatType,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;
  bool get canHaveChildren => level < 4;

  bool get isOverdue {
    if (dueDate == null || isDone) return false;
    final dueDay = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return dueDay.isBefore(today);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'task_id': taskId,
      'parent_id': parentId,
      'level': level,
      'title': title,
      'is_done': isDone ? 1 : 0,
      'sort_order': sortOrder,
      'due_date': dueDate?.toIso8601String(),
      'reminder_time': reminderTime?.toIso8601String(),
      'repeat_type': repeatType,
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory SubTask.fromMap(Map<String, dynamic> map) {
    return SubTask(
      id: map['id'],
      taskId: map['task_id'],
      parentId: map['parent_id'],
      level: map['level'] ?? 0,
      title: map['title'],
      isDone: map['is_done'] == 1,
      sortOrder: map['sort_order'] ?? 0,
      dueDate: map['due_date'] != null ? DateTime.parse(map['due_date']) : null,
      reminderTime: map['reminder_time'] != null ? DateTime.parse(map['reminder_time']) : null,
      repeatType: map['repeat_type'] as String?,
      deletedAt: map['deleted_at'] != null ? DateTime.parse(map['deleted_at']) : null,
    );
  }

  SubTask copyWith({
    int? id,
    int? taskId,
    int? parentId,
    bool clearParentId = false,
    int? level,
    String? title,
    bool? isDone,
    int? sortOrder,
    DateTime? dueDate,
    DateTime? reminderTime,
    DateTime? deletedAt,
    String? repeatType,
    bool clearRepeatType = false,
    bool clearDueDate = false,
    bool clearReminderTime = false,
    bool clearDeletedAt = false,
  }) {
    return SubTask(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      level: level ?? this.level,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
      sortOrder: sortOrder ?? this.sortOrder,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      reminderTime: clearReminderTime ? null : (reminderTime ?? this.reminderTime),
      repeatType: clearRepeatType ? null : (repeatType ?? this.repeatType),
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}
