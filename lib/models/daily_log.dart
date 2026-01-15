import 'package:cloud_firestore/cloud_firestore.dart';

class DailyLog {
  final String dateStr; // YYYY-MM-DD
  final bool complete;
  final DateTime lastUpdated;
  final DateTime? lastPlannedAt; // When was the plan first created/substantially modified?
  final int? score; // Cache the score here for easy access

  DailyLog({
    required this.dateStr,
    required this.complete,
    required this.lastUpdated,
    this.lastPlannedAt,
    this.score,
  });

  Map<String, dynamic> toMap() {
    return {
      'date': dateStr,
      'complete': complete,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
      if (lastPlannedAt != null) 'lastPlannedAt': Timestamp.fromDate(lastPlannedAt!),
      if (score != null) 'score': score,
    };
  }

  factory DailyLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DailyLog(
      dateStr: data['date'] as String? ?? '',
      complete: data['complete'] as bool? ?? false,
      lastUpdated: (data['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastPlannedAt: (data['lastPlannedAt'] as Timestamp?)?.toDate(),
      score: data['score'] as int?,
    );
  }
}
