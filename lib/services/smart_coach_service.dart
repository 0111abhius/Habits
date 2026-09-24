import 'dart:math';
import '../models/coach_fact.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/daily_score.dart';

class SmartCoachService {
  static final SmartCoachService _instance = SmartCoachService._internal();
  factory SmartCoachService() => _instance;
  SmartCoachService._internal();

  final Random _random = Random();

  // Repository of "Eternal Facts"
  final List<CoachFact> _facts = const [
    // Planning Facts
    CoachFact(
      text: "Every minute you spend in planning saves 10 minutes in execution.",
      source: "Brian Tracy",
      category: FactCategory.planning,
    ),
    CoachFact(
      text: "Writing down your goals increases the likelihood of achieving them by 42%.",
      source: "Dominican University Study",
      category: FactCategory.planning,
    ),
    CoachFact(
      text: "The most successful people plan their day the night before.",
      source: "Productivity Best Practices",
      category: FactCategory.planning,
    ),
    CoachFact(
      text: "A plan is not about predicting the future, it's about making better decisions in the present.",
      source: "Strategic Thinking",
      category: FactCategory.planning,
    ),
    
    // Retrospective Facts
    CoachFact(
      text: "Reflection transforms experience into insight.",
      source: "John Maxwell",
      category: FactCategory.retrospective,
    ),
    CoachFact(
      text: "We do not learn from experience... we learn from reflecting on experience.",
      source: "John Dewey",
      category: FactCategory.retrospective,
    ),
    CoachFact(
      text: "The Zeigarnik effect states that people remember uncompleted or interrupted tasks better than completed tasks. A retro helps close these loops.",
      source: "Psychology Principle",
      category: FactCategory.retrospective,
    ),

    // Productivity
    CoachFact(
      text: "Multi-tasking reduces productivity by up to 40%.",
      source: "American Psychological Association",
      category: FactCategory.productivity,
    ),
    CoachFact(
      text: "Focus is not saying yes to the thing you've got to focus on. It means saying no to the hundred other good ideas.",
      source: "Steve Jobs",
      category: FactCategory.productivity,
    ),
    CoachFact(
      text: "The key is not to prioritize what's on your schedule, but to schedule your priorities.",
      source: "Stephen Covey",
      category: FactCategory.productivity,
    ),

    // Wellness / General
    CoachFact(
      text: "Rest is not idleness, and to lie sometimes on the grass under trees on a summer's day... is by no means a waste of time.",
      source: "John Lubbock",
      category: FactCategory.wellness,
    ),
    CoachFact(
      text: "Almost everything will work again if you unplug it for a few minutes, including you.",
      source: "Anne Lamott",
      category: FactCategory.wellness,
    ),
  ];

  CoachFact getRandomFact({FactCategory? category}) {
    List<CoachFact> candidates = _facts;
    if (category != null) {
      candidates = _facts.where((f) => f.category == category).toList();
      if (candidates.isEmpty) candidates = _facts; // Fallback
    }
    return candidates[_random.nextInt(candidates.length)];
  }

  /// Loads the last 30 days of daily logs and derives a data-backed insight.
  ///
  /// `daily_logs/{uid}/logs/{yyyy-MM-dd}` documents store `date` as a
  /// `yyyy-MM-dd` string and the computed score nested under `scoreDetails`,
  /// so we compare against a string bound and unwrap the nested map.
  Future<CoachInsight?> generateInsight(String userId, {FirebaseFirestore? firestore}) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
    final startStr = DateFormat('yyyy-MM-dd').format(start);

    List<DailyScore> scores = [];
    try {
      final QuerySnapshot snapshot = await db
          .collection('daily_logs')
          .doc(userId)
          .collection('logs')
          .where('date', isGreaterThanOrEqualTo: startStr)
          .get();
      scores = parseScores(snapshot.docs.map((d) => d.data() as Map<String, dynamic>));
    } catch (_) {
      return _getGeneralMotivation();
    }

    return analyzeScores(scores) ?? _getGeneralMotivation();
  }

  /// Extracts [DailyScore]s from raw daily log documents, skipping days that
  /// were never scored.
  static List<DailyScore> parseScores(Iterable<Map<String, dynamic>> docs) {
    final List<DailyScore> scores = [];
    for (final data in docs) {
      final details = data['scoreDetails'];
      if (details is Map) {
        try {
          scores.add(DailyScore.fromMap(Map<String, dynamic>.from(details)));
        } catch (_) {
          // Ignore malformed legacy entries.
        }
      }
    }
    return scores;
  }

  /// Pure analysis step; returns null when there is not enough signal.
  CoachInsight? analyzeScores(List<DailyScore> scores) {
    if (scores.length < 5) return null;

    // 2. Analyze Planning Impact
    final plannedDays = scores.where((s) => (s.breakdown['planning'] ?? 0) > 10).toList();
    final unplannedDays = scores.where((s) => (s.breakdown['planning'] ?? 0) <= 10).toList();

    double avgPlanned = _calcAvg(plannedDays);
    double avgUnplanned = _calcAvg(unplannedDays);

    // 3. Analyze Retro Impact
    final retroDays = scores.where((s) => (s.breakdown['retro'] ?? 0) > 10).toList();
    final noRetroDays = scores.where((s) => (s.breakdown['retro'] ?? 0) <= 10).toList();

    double avgRetro = _calcAvg(retroDays);
    double avgNoRetro = _calcAvg(noRetroDays);
    
    // 4. Decide on Insight
    // We prioritize "Coach" facts (studies) and use data to support them.
    
    bool showPlanInsight = (plannedDays.isNotEmpty && unplannedDays.isNotEmpty && avgPlanned > (avgUnplanned + 10));
    bool showRetroInsight = (retroDays.isNotEmpty && noRetroDays.isNotEmpty && avgRetro > (avgNoRetro + 10));

    // Randomly pick one if both are true to vary the experience
    if (showPlanInsight && showRetroInsight) {
      if (_random.nextBool()) showPlanInsight = false;
      else showRetroInsight = false;
    }

    if (showPlanInsight) {
      final fact = getRandomFact(category: FactCategory.planning);
      // "Substance" format: Fact + Personal Data confirmation
      return CoachInsight(
        message: "${fact.text}\n\nYour data backs this up: you average ${(avgPlanned - avgUnplanned).round()} more points on days you plan.",
        type: InsightType.planning,
      );
    }
    
    if (showRetroInsight) {
      final fact = getRandomFact(category: FactCategory.retrospective);
       return CoachInsight(
        message: "${fact.text}\n\nYou tend to end the day ${(avgRetro - avgNoRetro).round()} points higher or happier when you take time to reflect.",
        type: InsightType.retro,
      );
    }

    return null;
  }

  double _calcAvg(List<DailyScore> list) {
    if (list.isEmpty) return 0;
    return list.map((s) => s.totalScore).reduce((a, b) => a + b) / list.length;
  }

  CoachInsight _getGeneralMotivation() {
    final fact = getRandomFact(category: FactCategory.productivity);
    return CoachInsight(
      message: fact.text, 
      type: InsightType.general
    );
  }
}

class CoachInsight {
  final String message;
  final InsightType type;
  
  CoachInsight({required this.message, required this.type});
}

enum InsightType {
  planning,
  retro,
  general,
}
