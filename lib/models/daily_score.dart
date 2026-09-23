import 'package:cloud_firestore/cloud_firestore.dart';

class DailyScore {
  final String userId;
  final DateTime date;
  final int totalScore;
  final Map<String, int> breakdown; // 'planning', 'retro', 'execution', 'goal'
  final String aiGoalAnalysis;
  final String coachTip;
  final DateTime computedAt;
  final Map<String, dynamic> nutrition;

  DailyScore({
    required this.userId,
    required this.date,
    required this.totalScore,
    this.breakdown = const {},
    this.aiGoalAnalysis = '',
    this.coachTip = '',
    required this.computedAt,
    this.nutrition = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'date': Timestamp.fromDate(date),
      'totalScore': totalScore,
      'breakdown': breakdown,
      'aiGoalAnalysis': aiGoalAnalysis,
      'coachTip': coachTip,
      'computedAt': Timestamp.fromDate(computedAt),
      'nutrition': nutrition,
    };
  }

  factory DailyScore.fromFirestore(DocumentSnapshot doc) {
    return DailyScore.fromMap(doc.data() as Map<String, dynamic>);
  }

  factory DailyScore.fromMap(Map<String, dynamic> data) {
    final rawDate = data['date'];
    final DateTime date = rawDate is Timestamp
        ? rawDate.toDate()
        : rawDate is String
            ? (DateTime.tryParse(rawDate) ?? DateTime.now())
            : DateTime.now();
    final rawBreakdown = data['breakdown'];
    final breakdown = <String, int>{};
    if (rawBreakdown is Map) {
      rawBreakdown.forEach((k, v) {
        if (v is num) breakdown[k.toString()] = v.toInt();
      });
    }
    return DailyScore(
      userId: data['userId'] as String? ?? '',
      date: date,
      totalScore: (data['totalScore'] as num?)?.toInt() ?? 0,
      breakdown: breakdown,
      aiGoalAnalysis: data['aiGoalAnalysis'] as String? ?? '',
      coachTip: data['coachTip'] as String? ?? '',
      computedAt: (data['computedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      nutrition: data['nutrition'] as Map<String, dynamic>? ?? {},
    );
  }
}
