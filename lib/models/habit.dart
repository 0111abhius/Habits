import 'package:cloud_firestore/cloud_firestore.dart';

enum HabitFrequency {
  daily,
  threeTimesWeek,
}

enum HabitType {
  binary,
  counter,
}

class Habit {
  final String id;
  final String name;
  final HabitType type;
  final HabitFrequency frequency;
  final String userId;
  final List<DateTime> completedDates;
  final DateTime createdAt;

  Habit({
    required this.id,
    required this.name,
    required this.type,
    required this.frequency,
    required this.userId,
    required this.completedDates,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type.toString().split('.').last,
      'frequency': frequency.toString().split('.').last,
      'userId': userId,
      'completedDates': completedDates.map((date) => Timestamp.fromDate(date)).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory Habit.fromMap(String id, Map<String, dynamic> map) {
    return Habit(
      id: id,
      name: map['name'] as String,
      type: HabitType.values.firstWhere(
        (e) => e.toString().split('.').last == (map['type'] ?? 'binary'),
      ),
      frequency: HabitFrequency.values.firstWhere(
        (e) => e.toString().split('.').last == map['frequency'],
      ),
      userId: map['userId'] as String,
      completedDates: (map['completedDates'] as List<dynamic>)
          .map((date) => (date as Timestamp).toDate())
          .toList(),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }

  Habit copyWith({
    String? name,
    HabitType? type,
    HabitFrequency? frequency,
    List<DateTime>? completedDates,
  }) {
    return Habit(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      frequency: frequency ?? this.frequency,
      userId: userId,
      completedDates: completedDates ?? this.completedDates,
      createdAt: createdAt,
    );
  }
} 