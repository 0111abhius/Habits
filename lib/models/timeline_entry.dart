import 'package:cloud_firestore/cloud_firestore.dart';

class TimelineEntry {
  final String id;
  final String userId;
  final DateTime date;
  final DateTime startTime;
  final DateTime endTime;
  final String planactivity;
  final String planNotes;
  final String activity;
  final String notes;

  /// Anchor slot: planners (AI, "place into work blocks") must not overwrite it.
  final bool locked;

  /// Flexible work slot that prioritized tasks can be placed into.
  final bool workBlock;

  /// Task that was placed into this slot, if any.
  final String? taskId;

  TimelineEntry({
    required this.id,
    required this.userId,
    required this.date,
    required this.startTime,
    required this.endTime,
    this.planactivity = '',
    this.planNotes = '',
    required this.activity,
    required this.notes,
    this.locked = false,
    this.workBlock = false,
    this.taskId,
  });

  Duration get duration => endTime.difference(startTime);

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'date': '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'hour': startTime.hour,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'planactivity': planactivity,
      'planNotes': planNotes,
      'activity': activity,
      'notes': notes,
      if (locked) 'locked': true,
      if (workBlock) 'workBlock': true,
      if (taskId != null) 'taskId': taskId,
    };
  }

  factory TimelineEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TimelineEntry.fromMap(doc.id, data);
  }

  factory TimelineEntry.fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDateField(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is String) {
        final parts = raw.split('-');
        return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      }
      return DateTime.now();
    }

    return TimelineEntry(
      id: id,
      userId: data['userId'] as String? ?? '',
      date: parseDateField(data['date']),
      startTime: (data['startTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endTime: (data['endTime'] as Timestamp?)?.toDate() ?? DateTime.now().add(const Duration(hours: 1)),
      planactivity: data['planactivity'] as String? ?? '',
      planNotes: data['planNotes'] as String? ?? '',
      activity: data['activity'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      locked: data['locked'] == true,
      workBlock: data['workBlock'] == true,
      taskId: data['taskId'] as String?,
    );
  }

  factory TimelineEntry.empty() {
    return TimelineEntry(
      id: '',
      userId: '',
      date: DateTime.now(),
      startTime: DateTime.now(),
      endTime: DateTime.now(),
      activity: '',
      notes: '',
    );
  }
}
