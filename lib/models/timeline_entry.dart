import 'package:cloud_firestore/cloud_firestore.dart';

class TimelineEntry {
  final String id;
  final String userId;
  final DateTime date;
  final DateTime startTime;
  final DateTime endTime;
  final String planCategory;
  final String planNotes;
  final String category;
  final String notes;

  TimelineEntry({
    required this.id,
    required this.userId,
    required this.date,
    required this.startTime,
    required this.endTime,
    this.planCategory = '',
    this.planNotes = '',
    required this.category,
    required this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'date': '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'hour': startTime.hour,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'planCategory': planCategory,
      'planNotes': planNotes,
      'category': category,
      'notes': notes,
    };
  }

  factory TimelineEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    DateTime parseDateField(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is String) {
        final parts = raw.split('-');
        return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      }
      return DateTime.now();
    }

    return TimelineEntry(
      id: doc.id,
      userId: data['userId'] as String,
      date: parseDateField(data['date']),
      startTime: (data['startTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endTime: (data['endTime'] as Timestamp?)?.toDate() ?? DateTime.now().add(const Duration(hours: 1)),
      planCategory: data['planCategory'] as String? ?? '',
      planNotes: data['planNotes'] as String? ?? '',
      category: data['category'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
    );
  }
} 