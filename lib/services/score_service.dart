import 'package:flutter/material.dart';
import '../models/timeline_entry.dart';
import '../models/user_settings.dart';
import '../models/daily_log.dart';
import '../models/daily_score.dart';
import '../utils/ai_service.dart';

class ScoreService {
  Future<DailyScore> calculateDailyScore({
    required String userId,
    required DateTime date,
    required List<TimelineEntry> entries,
    required DailyLog? log,
    required UserSettings settings,
  }) async {
    final weights = settings.scoreWeights;
    
    // 1. Planning Score
    int planningScore = _calculatePlanningScore(entries, log, settings);
    
    // 2. Retro Score
    int retroScore = _calculateRetroScore(entries);
    
    // 3. Execution Score
    int executionScore = _calculateExecutionScore(entries);
    
    // 4. Goal Alignment (AI Powered)
    final aiResult = await _calculateGoalAnalysisAI(entries, settings.goalText);
    int goalScore = aiResult['score'] as int? ?? 50;
    String aiAnalysis = aiResult['analysis'] as String? ?? "Analysis unavailable.";
    String tip = aiResult['tip'] as String? ?? "";
    
    // Final Weighted Average
    double total = 
        (planningScore * (weights['planning'] ?? 20)) +
        (retroScore * (weights['retro'] ?? 20)) +
        (executionScore * (weights['execution'] ?? 30)) +
        (goalScore * (weights['goal'] ?? 30)) as double;
        
    int finalScore = (total / 100).round();

    return DailyScore(
      userId: userId,
      date: date,
      totalScore: finalScore,
      breakdown: {
        'planning': planningScore,
        'retro': retroScore,
        'execution': executionScore,
        'goal': goalScore,
      },
      aiGoalAnalysis: aiAnalysis,
      coachTip: tip,
      computedAt: DateTime.now(),
    );
  }

  Future<Map<String, dynamic>> _calculateGoalAnalysisAI(List<TimelineEntry> entries, String goal) async {
    if (goal.isEmpty) {
      return {'score': 100, 'analysis': 'No specific goal set, assuming full alignment.', 'tip': 'Set a goal in settings!'};
    }
    
    // Format logs
    List<String> logs = entries.where((e) => e.activity.isNotEmpty).map((e) {
      return "${e.startTime.hour}:${e.startTime.minute.toString().padLeft(2,'0')} - ${e.activity} ${e.notes.isNotEmpty ? '(${e.notes})' : ''}";
    }).toList();
    
    if (logs.isEmpty) {
      return {'score': 0, 'analysis': 'No activities logged.', 'tip': 'Log your day to get a score.'};
    }

    return await AIService().analyzeGoalAlignment(goal: goal, logs: logs);
  }

  int _calculatePlanningScore(List<TimelineEntry> entries, DailyLog? log, UserSettings settings) {
    if (log == null || log.lastPlannedAt == null) return 0;

    // Timing Check
    // Create DateTime for the target time on the *same day* as the log (or day it was planned?)
    // Actually, comparison should depend on if lastPlannedAt was *before* the target time on the target day?
    // Usually log.lastPlannedAt should be compared to "Date of Log + Target Time".
    // But if I plan *yesterday*, lastPlannedAt will be < Today 10AM. Correct.
    
    final targetDateTime = DateTime(
      log.lastPlannedAt!.year, log.lastPlannedAt!.month, log.lastPlannedAt!.day, 
      settings.planningTargetTime.hour, settings.planningTargetTime.minute
    );
    // If planned date-day is BEFORE the log date-day, huge bonus/success.
    // Simplifying: Just compare hours if it's same day.
    
    bool isTimely = false;
    // Check if planned *before* the target cutoff of the *activity day*.
    final activityDayCutoff = DateTime(
      entries.first.date.year, entries.first.date.month, entries.first.date.day,
      settings.planningTargetTime.hour, settings.planningTargetTime.minute
    );
    
    if (log.lastPlannedAt!.isBefore(activityDayCutoff)) {
      isTimely = true;
    }

    // Coverage Check (Hours planned)
    int hoursPlanned = entries.where((e) => e.planactivity.isNotEmpty).length;
    double coveragePct = (hoursPlanned / 12).clamp(0.0, 1.0); // Assume 12 active hours is "Full"
    
    int score = (coveragePct * 100).round();
    if (isTimely) score += 20; // Bonus for timeliness
    
    return score.clamp(0, 100);
  }

  int _calculateRetroScore(List<TimelineEntry> entries) {
    int hoursLogged = entries.where((e) => e.activity.isNotEmpty).length;
    int notesCount = entries.where((e) => e.notes.isNotEmpty).length;
    
    double coveragePct = (hoursLogged / 12).clamp(0.0, 1.0);
    // Bonus for meaningful notes
    double notesBonus = (notesCount / 5).clamp(0.0, 1.0) * 20; 
    
    return ((coveragePct * 80) + notesBonus).round().clamp(0, 100);
  }

  int _calculateExecutionScore(List<TimelineEntry> entries) {
    int plannedHours = entries.where((e) => e.planactivity.isNotEmpty).length;
    if (plannedHours == 0) return 0; // Can't execute a missing plan
    
    int matches = entries.where((e) => 
      e.planactivity.isNotEmpty && 
      e.activity.isNotEmpty &&
      _activitiesMatch(e.planactivity, e.activity)
    ).length;
    
    return ((matches / plannedHours) * 100).round();
  }

  bool _activitiesMatch(String plan, String actual) {
    return plan.trim().toLowerCase() == actual.trim().toLowerCase();
  }
}
