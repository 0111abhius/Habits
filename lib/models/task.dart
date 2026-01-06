import 'package:cloud_firestore/cloud_firestore.dart';

class Task {
  final String id;
  final String userId;
  final String title;
  final bool isCompleted;
  final bool isToday;
  final int estimatedMinutes; // 30, 60, 90, etc.
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? folder;

  Task({
    required this.id,
    required this.userId,
    required this.title,
    this.isCompleted = false,
    this.isToday = false,
    this.estimatedMinutes = 30,
    required this.createdAt,
    this.completedAt,
    this.folder,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'isCompleted': isCompleted,
      'isToday': isToday,
      'estimatedMinutes': estimatedMinutes,
      'createdAt': Timestamp.fromDate(createdAt),
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'folder': folder,
    };
  }

  factory Task.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Task(
      id: doc.id,
      userId: data['userId'] ?? '',
      title: data['title'] ?? '',
      isCompleted: data['isCompleted'] ?? false,
      isToday: data['isToday'] ?? false,
      estimatedMinutes: data['estimatedMinutes'] ?? 30,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      folder: data['folder'] as String?,
    );
  }

  Task copyWith({
    String? title,
    bool? isCompleted,
    bool? isToday,
    int? estimatedMinutes,
    DateTime? completedAt,
    String? folder,
  }) {
    return Task(
      id: id,
      userId: userId,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      isToday: isToday ?? this.isToday,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
      folder: folder ?? this.folder,
    );
  }
}
