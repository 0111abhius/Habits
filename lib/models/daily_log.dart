import 'package:cloud_firestore/cloud_firestore.dart';

class DailyLog {
  final String dateStr; // YYYY-MM-DD
  final bool complete;
  final DateTime lastUpdated;
  final DateTime? lastPlannedAt; // When was the plan first created/substantially modified?
  final int? score; // Cache the score here for easy access
  final Map<String, String>? sectionNotes;

  DailyLog({
    required this.dateStr,
    required this.complete,
    required this.lastUpdated,
    this.lastPlannedAt,
    this.score,
    this.sectionNotes,
  });

  Map<String, dynamic> toMap() {
    return {
      'date': dateStr,
      'complete': complete,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
      if (lastPlannedAt != null) 'lastPlannedAt': Timestamp.fromDate(lastPlannedAt!),
      if (score != null) 'score': score,
      if (sectionNotes != null) 'sectionNotes': sectionNotes,
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
      sectionNotes: (data['sectionNotes'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())),
    );
  }
}
