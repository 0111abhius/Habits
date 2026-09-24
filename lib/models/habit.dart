import 'package:cloud_firestore/cloud_firestore.dart';

enum HabitFrequency {
  /// Expected every day.
  daily,

  /// Expected [Habit.weeklyTarget] times per calendar week (Mon-Sun).
  weekly,
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

  /// For [HabitFrequency.weekly]: how many days per week count as success.
  final int weeklyTarget;

  /// For [HabitType.counter]: daily goal. A day counts as done when the
  /// logged value reaches this number.
  final int targetCount;
  final String userId;
  final List<DateTime> completedDates;
  final DateTime createdAt;
  final bool archived;
  final int sortOrder;

  /// Optional `HH:mm` reminder time (used by web reminders).
  final String? reminderTime;

  /// Denormalized log: `yyyy-MM-dd` -> value logged that day
  /// (1/0 for binary habits, count for counter habits).
  final Map<String, int> history;

  Habit({
    required this.id,
    required this.name,
    required this.type,
    required this.frequency,
    this.weeklyTarget = 3,
    this.targetCount = 1,
    required this.userId,
    this.completedDates = const [],
    required this.createdAt,
    this.archived = false,
    this.sortOrder = 0,
    this.reminderTime,
    this.history = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type.name,
      'frequency': frequency.name,
      'weeklyTarget': weeklyTarget,
      'targetCount': targetCount,
      'userId': userId,
      'completedDates': completedDates.map((date) => Timestamp.fromDate(date)).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      'archived': archived,
      'sortOrder': sortOrder,
      'reminderTime': reminderTime,
      'history': history,
    };
  }

  factory Habit.fromMap(String id, Map<String, dynamic> map) {
    final rawFreq = (map['frequency'] as String?) ?? 'daily';
    // Legacy value from the first version of the app.
    final frequency = rawFreq == 'threeTimesWeek'
        ? HabitFrequency.weekly
        : HabitFrequency.values.firstWhere(
            (e) => e.name == rawFreq,
            orElse: () => HabitFrequency.daily,
          );
    final weeklyTarget = rawFreq == 'threeTimesWeek'
        ? 3
        : ((map['weeklyTarget'] as num?)?.toInt() ?? 3);

    final rawHistory = map['history'];
    final Map<String, int> history = {};
    if (rawHistory is Map) {
      rawHistory.forEach((k, v) {
        if (v is num) {
          history[k.toString()] = v.toInt();
        } else if (v is bool) {
          history[k.toString()] = v ? 1 : 0;
        }
      });
    }

    return Habit(
      id: id,
      name: map['name'] as String? ?? '',
      type: HabitType.values.firstWhere(
        (e) => e.name == (map['type'] ?? 'binary'),
        orElse: () => HabitType.binary,
      ),
      frequency: frequency,
      weeklyTarget: weeklyTarget.clamp(1, 7),
      targetCount: ((map['targetCount'] as num?)?.toInt() ?? 1).clamp(1, 1000),
      userId: map['userId'] as String? ?? '',
      completedDates: ((map['completedDates'] as List<dynamic>?) ?? const [])
          .whereType<Timestamp>()
          .map((date) => date.toDate())
          .toList(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      archived: map['archived'] as bool? ?? false,
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      reminderTime: map['reminderTime'] as String?,
      history: history,
    );
  }

  Habit copyWith({
    String? name,
    HabitType? type,
    HabitFrequency? frequency,
    int? weeklyTarget,
    int? targetCount,
    List<DateTime>? completedDates,
    bool? archived,
    int? sortOrder,
    String? reminderTime,
    bool clearReminder = false,
    Map<String, int>? history,
  }) {
    return Habit(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      frequency: frequency ?? this.frequency,
      weeklyTarget: weeklyTarget ?? this.weeklyTarget,
      targetCount: targetCount ?? this.targetCount,
      userId: userId,
      completedDates: completedDates ?? this.completedDates,
      createdAt: createdAt,
      archived: archived ?? this.archived,
      sortOrder: sortOrder ?? this.sortOrder,
      reminderTime: clearReminder ? null : (reminderTime ?? this.reminderTime),
      history: history ?? this.history,
    );
  }

  /// Human readable cadence, e.g. "Every day" or "4x / week".
  String get frequencyLabel =>
      frequency == HabitFrequency.daily ? 'Every day' : '${weeklyTarget}x / week';
}
