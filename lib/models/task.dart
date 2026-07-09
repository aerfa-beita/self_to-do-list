class Task {
  final int? id;
  final String title;
  final String note;
  final String category;
  final DateTime createdAt;
  final DateTime? completedAt;
  final DateTime? deletedAt;
  final DateTime? dueDate;
  final DateTime? reminderTime;
  final String? repeatType; // null=不重复, 'daily', 'weekly', 'monthly'
  final int sortOrder;

  Task({
    this.id,
    required this.title,
    this.note = '',
    this.category = '默认',
    DateTime? createdAt,
    this.completedAt,
    this.deletedAt,
    this.dueDate,
    this.reminderTime,
    this.repeatType,
    this.sortOrder = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isDeleted => deletedAt != null;
  bool get isCompleted => completedAt != null;
  /// 只看日期不看时间：今天不算过期
  bool get isOverdue {
    if (dueDate == null || isCompleted) return false;
    final dueDay = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
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
      'deleted_at': deletedAt?.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'reminder_time': reminderTime?.toIso8601String(),
      'repeat_type': repeatType,
      'sort_order': sortOrder,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'],
      title: map['title'],
      note: map['note'] ?? '',
      category: map['category'] ?? '默认',
      createdAt: DateTime.parse(map['created_at']),
      completedAt: map['completed_at'] != null ? DateTime.parse(map['completed_at']) : null,
      deletedAt: map['deleted_at'] != null ? DateTime.parse(map['deleted_at']) : null,
      dueDate: map['due_date'] != null ? DateTime.parse(map['due_date']) : null,
      reminderTime: map['reminder_time'] != null ? DateTime.parse(map['reminder_time']) : null,
      repeatType: map['repeat_type'] as String?,
      sortOrder: map['sort_order'] ?? 0,
    );
  }

  Task copyWith({
    int? id,
    String? title,
    String? note,
    String? category,
    DateTime? createdAt,
    DateTime? completedAt,
    DateTime? deletedAt,
    DateTime? dueDate,
    DateTime? reminderTime,
    int? sortOrder,
    bool clearCompletedAt = false,
    bool clearDeletedAt = false,
    String? repeatType,
    bool clearRepeatType = false,
    bool clearDueDate = false,
    bool clearReminderTime = false,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      note: note ?? this.note,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      reminderTime: clearReminderTime ? null : (reminderTime ?? this.reminderTime),
      repeatType: clearRepeatType ? null : (repeatType ?? this.repeatType),
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
