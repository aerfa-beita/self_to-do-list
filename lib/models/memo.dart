/// 备忘录模型——纯文本便签，支持5级嵌套
class Memo {
  final int? id;
  final int? parentId;   // null=根节点
  final int level;        // 0~4，共5层
  final String content;
  final String category;
  final int sortOrder;
  final DateTime? dueDate;
  final DateTime? reminderTime;
  final String? repeatType;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Memo({
    this.id,
    this.parentId,
    this.level = 0,
    required this.content,
    this.category = '紧急+重要+必须',
    this.sortOrder = 0,
    this.dueDate,
    this.reminderTime,
    this.repeatType,
    this.deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isDeleted => deletedAt != null;
  bool get canHaveChildren => level < 4;

  bool get isOverdue {
    if (dueDate == null) return false;
    final dueDay = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return dueDay.isBefore(today);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'parent_id': parentId,
      'level': level,
      'content': content,
      'category': category,
      'sort_order': sortOrder,
      'due_date': dueDate?.toIso8601String(),
      'reminder_time': reminderTime?.toIso8601String(),
      'repeat_type': repeatType,
      'deleted_at': deletedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Memo.fromMap(Map<String, dynamic> map) {
    return Memo(
      id: map['id'],
      parentId: map['parent_id'],
      level: map['level'] ?? 0,
      content: map['content'],
      category: map['category'] ?? '紧急+重要+必须',
      sortOrder: map['sort_order'] ?? 0,
      dueDate: map['due_date'] != null ? DateTime.parse(map['due_date']) : null,
      reminderTime: map['reminder_time'] != null ? DateTime.parse(map['reminder_time']) : null,
      repeatType: map['repeat_type'] as String?,
      deletedAt: map['deleted_at'] != null ? DateTime.parse(map['deleted_at']) : null,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  Memo copyWith({
    int? id,
    int? parentId,
    bool clearParentId = false,
    int? level,
    String? content,
    String? category,
    int? sortOrder,
    DateTime? dueDate,
    DateTime? reminderTime,
    DateTime? deletedAt,
    String? repeatType,
    bool clearRepeatType = false,
    bool clearDueDate = false,
    bool clearReminderTime = false,
    bool clearDeletedAt = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Memo(
      id: id ?? this.id,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      level: level ?? this.level,
      content: content ?? this.content,
      category: category ?? this.category,
      sortOrder: sortOrder ?? this.sortOrder,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      reminderTime: clearReminderTime ? null : (reminderTime ?? this.reminderTime),
      repeatType: clearRepeatType ? null : (repeatType ?? this.repeatType),
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
