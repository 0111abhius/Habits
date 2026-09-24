import 'package:cloud_firestore/cloud_firestore.dart';

class Task {
  final String id;
  final String userId;
  final String title;
  final String notes;
  final bool isCompleted;
  final bool isToday;
  final int estimatedMinutes; // 30, 60, 90, etc.
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? folder;
  final DateTime? scheduledDate;
  final String? activity;

  /// Manual position within its folder (lower comes first). Defaults to the
  /// creation timestamp so legacy tasks keep a stable order.
  final int sortOrder;

  Task({
    required this.id,
    required this.userId,
    required this.title,
    this.notes = '',
    this.isCompleted = false,
    this.isToday = false,
    this.estimatedMinutes = 30,
    required this.createdAt,
    this.completedAt,
    this.folder,
    this.scheduledDate,
    this.activity,
    int? sortOrder,
  }) : sortOrder = sortOrder ?? createdAt.millisecondsSinceEpoch;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'notes': notes,
      'isCompleted': isCompleted,
      'isToday': isToday,
      'estimatedMinutes': estimatedMinutes,
      'createdAt': Timestamp.fromDate(createdAt),
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'folder': folder,
      'scheduledDate': scheduledDate != null ? Timestamp.fromDate(scheduledDate!) : null,
      'activity': activity,
      'sortOrder': sortOrder,
    };
  }

  factory Task.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    return Task(
      id: doc.id,
      userId: data['userId'] ?? '',
      title: data['title'] ?? '',
      notes: data['notes'] as String? ?? '',
      isCompleted: data['isCompleted'] ?? false,
      isToday: data['isToday'] ?? false,
      estimatedMinutes: (data['estimatedMinutes'] as num?)?.toInt() ?? 30,
      createdAt: createdAt,
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      folder: data['folder'] as String?,
      scheduledDate: (data['scheduledDate'] as Timestamp?)?.toDate(),
      activity: data['activity'] as String?,
      sortOrder: (data['sortOrder'] as num?)?.toInt(),
    );
  }

  Task copyWith({
    String? title,
    String? notes,
    bool? isCompleted,
    bool? isToday,
    int? estimatedMinutes,
    DateTime? completedAt,
    String? folder,
    DateTime? scheduledDate,
    String? activity,
    int? sortOrder,
  }) {
    return Task(
      id: id,
      userId: userId,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      isCompleted: isCompleted ?? this.isCompleted,
      isToday: isToday ?? this.isToday,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
      folder: folder ?? this.folder,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      activity: activity ?? this.activity,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// "1h", "1.5h", "45m" style label for the estimate.
  String get estimateLabel {
    if (estimatedMinutes <= 0) return '';
    if (estimatedMinutes < 60) return '${estimatedMinutes}m';
    final h = estimatedMinutes / 60;
    return h == h.roundToDouble() ? '${h.toInt()}h' : '${h.toStringAsFixed(1)}h';
  }

  bool get isOverdue {
    if (isCompleted || scheduledDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(scheduledDate!.year, scheduledDate!.month, scheduledDate!.day);
    return d.isBefore(today);
  }
}
