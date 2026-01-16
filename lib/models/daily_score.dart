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
    final data = doc.data() as Map<String, dynamic>;
    return DailyScore(
      userId: data['userId'] as String? ?? '',
      date: (data['date'] as Timestamp).toDate(),
      totalScore: data['totalScore'] as int? ?? 0,
      breakdown: Map<String, int>.from(data['breakdown'] ?? {}),
      aiGoalAnalysis: data['aiGoalAnalysis'] as String? ?? '',
      coachTip: data['coachTip'] as String? ?? '',
      computedAt: (data['computedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      nutrition: data['nutrition'] as Map<String, dynamic>? ?? {},
    );
  }
}
