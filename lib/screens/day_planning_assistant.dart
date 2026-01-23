import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../models/timeline_entry.dart';
import '../models/task.dart';
import '../models/user_settings.dart';
import '../utils/ai_service.dart';
import '../widgets/ai_planning_dialogs.dart';
import '../main.dart'; // for getFirestore()

class DayPlanningAssistant {
  static Future<void> show(BuildContext context, DateTime date, List<TimelineEntry> currentEntries, List<String> availableActivities) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    String defaultGoal = '';
    TimeOfDay wakeTime = const TimeOfDay(hour: 7, minute: 0);
    TimeOfDay sleepTime = const TimeOfDay(hour: 23, minute: 0);

    if (uid != null) {
      try {
        final doc = await getFirestore().collection('user_settings').doc(uid).get();
        if (doc.exists) {
           final settings = UserSettings.fromMap(doc.data()!);
           defaultGoal = settings.goalText;
           wakeTime = settings.wakeTime;
           sleepTime = settings.sleepTime;
        }
      } catch (_) {}
    }

    // 1. Calculate Fullness heuristics upfront
    int wakeMin = wakeTime.hour * 60 + wakeTime.minute;
    int sleepMin = sleepTime.hour * 60 + sleepTime.minute;
    if (sleepMin < wakeMin) sleepMin += 24 * 60;
    
    final int activeDuration = sleepMin - wakeMin;
    int filledMinutes = 0;
    
    for (final e in currentEntries) {
         final act = e.planactivity.isNotEmpty ? e.planactivity : e.activity;
         if (act.isEmpty || act == 'Sleep') continue;
         
         int startM = e.startTime.hour * 60 + e.startTime.minute;
         int endM = e.endTime.hour * 60 + e.endTime.minute;
         if (endM == 0 && startM != 0) endM = 1440;
         if (endM < startM) endM += 1440;

         final int iterStart = startM < wakeMin ? wakeMin : startM;
         final int iterEnd = endM > sleepMin ? sleepMin : endM;
         
         if (iterEnd > iterStart) {
           filledMinutes += (iterEnd - iterStart);
         }
    }

    final int freeMinutes = activeDuration - filledMinutes;
    final bool isFull = freeMinutes <= 180; // <= 3 hours free

    // 2. Logic Fork
    if (isFull && defaultGoal.isNotEmpty) {
        // Auto-Feedback Path
        await _showFeedbackDialog(context, date, currentEntries, availableActivities, defaultGoal, isAuto: true);
    } else {
        // Standard Path
        final goal = await AIGoalDialog.show(
          context, 
          title: 'AI Day Planner', 
          promptLabel: 'Planning for ${DateFormat('MMM d').format(date)}.\nWhat is your main goal?',
          initialGoal: defaultGoal,
        );

        if (goal != null) {
           // Re-check fullness? Or just generate if not full?
           // If manually entered, we can probably respect the flow. 
           // If we ALREADY checked fullness and it WASN'T full, we go straight to plan.
           // If it WAS full but no default goal, we flow here. Then we check fullness again?
           // Yes, keep original logic for manual entry fallback.
           
           if (isFull) {
               await _showFeedbackDialog(context, date, currentEntries, availableActivities, goal, isAuto: false);
           } else {
               await _generatePlan(context, date, currentEntries, availableActivities, goal);
           }
        }
    }
  }

  static Future<void> _showFeedbackDialog(BuildContext context, DateTime date, List<TimelineEntry> entries, List<String> activities, String goal, {required bool isAuto}) async {
      // Loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );

      final currentPlan = _serializePlan(entries, []);
      final ai = AIService();
      final jsonResponse = await ai.getPlanFeedback(currentPlan: currentPlan, goal: goal);
      
      if (!context.mounted) return;
      Navigator.pop(context); // close loading

      int score = 0;
      String analysis = "Unable to analyze plan.";
      List<String> suggestions = [];

      try {
        final data = jsonDecode(jsonResponse);
        if (data is Map<String, dynamic>) {
           score = data['score'] as int? ?? 0;
           analysis = data['analysis'] as String? ?? '';
           suggestions = List<String>.from(data['suggestions'] ?? []);
        }
      } catch (e) {
        analysis = "AI Analysis Error: $jsonResponse";
      }

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Goal Alignment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isAuto && goal.isNotEmpty) ...[
                   Text('Based on goal: "$goal"', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                   const SizedBox(height: 8),
                ],
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      height: 80, width: 80,
                      child: CircularProgressIndicator(
                        value: score / 100,
                        backgroundColor: Colors.grey[200],
                        strokeWidth: 8,
                        color: score > 70 ? Colors.green : (score > 40 ? Colors.orange : Colors.red),
                      ),
                    ),
                    Text('$score%', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                Text(analysis, textAlign: TextAlign.center, style: const TextStyle(fontStyle: FontStyle.italic)),
                const SizedBox(height: 16),
                if (suggestions.isNotEmpty) ...[
                   const Align(alignment: Alignment.centerLeft, child: Text('Suggestions:', style: TextStyle(fontWeight: FontWeight.bold))),
                   const SizedBox(height: 8),
                   ...suggestions.map((s) => Padding(
                     padding: const EdgeInsets.only(bottom: 4.0),
                     child: Row(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                         Expanded(child: Text(s)),
                       ],
                     ),
                   )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Dismiss'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true), // Return true to proceed
              child: const Text('Proceed to Edit'),
            ),
          ],
        ),
      ).then((proceed) async {
         if (proceed == true) {
             // Open formatted Goal Dialog to allow editing
             final newGoal = await AIGoalDialog.show(
                context, 
                title: 'Refine Goal', 
                promptLabel: 'Edit your goal or context for replanning:',
                initialGoal: goal,
             );
             
             if (newGoal != null) {
                 await _generatePlan(context, date, entries, activities, newGoal);
             }
         }
      });
  }

  static String _serializePlan(List<TimelineEntry> entries, List<dynamic> tasks) { // simplified signature for now
      final buffer = StringBuffer();
      entries.sort((a,b)=>a.startTime.compareTo(b.startTime));
      for (final e in entries) {
        final time = DateFormat('HH:mm').format(e.startTime);
        final act = e.planactivity.isNotEmpty ? e.planactivity : e.activity;
        if (act.isNotEmpty) {
           buffer.writeln('$time - $act');
        }
      }
      // Add tasks summary if needed, for feedback we might skip tasks or include them if passed
      return buffer.toString().isEmpty ? '(No activities planned yet)' : buffer.toString();
  }

  static Future<void> _generatePlan(BuildContext context, DateTime date, List<TimelineEntry> entries, List<String> activities, String goal) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Serialize current plan
      final buffer = StringBuffer();
      // sort entries
      entries.sort((a,b)=>a.startTime.compareTo(b.startTime));
      // Capture original schedule for diffing later
      final Map<String, String> originalSchedule = {};

      for (final e in entries) {
        final time = DateFormat('HH:mm').format(e.startTime);
        final act = e.planactivity.isNotEmpty ? e.planactivity : e.activity;
        if (act.isNotEmpty) {
           buffer.writeln('$time - $act');
           originalSchedule[time] = act;
        }
      }
      
      // Fetch Tasks for Today
      // Fetch Tasks
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        // Fetch ALL incomplete tasks to prioritize
        final taskSnap = await getFirestore()
            .collection('tasks')
            .where('userId', isEqualTo: uid)
            .where('isCompleted', isEqualTo: false)
            .get();
        
        final allTasks = taskSnap.docs.map((d) => Task.fromFirestore(d)).toList();
        
        // Sorting Logic:
        // 1. Overdue (scheduled before today)
        // 2. Today (isToday=true OR scheduledDate=today)
        // 3. Tomorrow/Future (scheduledDate > today) -> Maybe exclude or put last?
        // 4. No Date / Inbox

        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);
        final tomorrowStart = todayStart.add(const Duration(days: 1));

        final List<Task> highPriority = [];
        final List<Task> otherTasks = [];

        for (final t in allTasks) {
           bool isOverdue = false;
           bool isToday = t.isToday;
           
           if (t.scheduledDate != null) {
             final d = DateTime(t.scheduledDate!.year, t.scheduledDate!.month, t.scheduledDate!.day);
             if (d.isBefore(todayStart)) isOverdue = true;
             if (d == todayStart) isToday = true;
           }

           if (isOverdue || isToday) {
             highPriority.add(t);
           } else {
             otherTasks.add(t);
           }
        }

        // Add to buffer
        if (highPriority.isNotEmpty) {
           buffer.writeln('\nURGENT / TODAY TITLES:');
           for (final t in highPriority) {
              final due = t.scheduledDate != null && t.scheduledDate!.isBefore(todayStart) ? ' [OVERDUE]' : '';
              buffer.writeln('- ${t.title} (${t.estimatedMinutes}m)$due');
           }
        }

        if (otherTasks.isNotEmpty) {
           buffer.writeln('\nOTHER AVAILABLE TASKS (Select if relevant to goal):');
           // Limit others to prevent context overflow (e.g. top 15 most recent or just standard)
           // For now take top 15
           for (final t in otherTasks.take(15)) {
              buffer.writeln('- ${t.title} (${t.estimatedMinutes}m)');
           }
        }
      }

      final currentPlan = buffer.toString().isEmpty ? '(No activities planned yet)' : buffer.toString();

      final ai = AIService();
      final jsonStr = await ai.getDayPlanSuggestions(
        currentPlan: currentPlan,
        goal: goal.isEmpty ? 'Productivity' : goal,
        existingActivities: activities,
      );

      if (!context.mounted) return;
      Navigator.pop(context); // loading

      try {
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        if (data.containsKey('error')) {
          _showError(context, 'AI Error: ${data['error']}');
          return;
        }

        // Use shared robust detection
        data['newActivities'] = AIService.detectNewActivities(data, activities);

        AIPlanReviewDialog.show(context, data, (schedule, newActivities) async {
             await _applyPlan(context, date, schedule, newActivities);
        }, originalSchedule: originalSchedule);

      } catch (e) {
        _showError(context, 'Failed to parse AI response.');
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        _showError(context, 'Error: $e');
      }
    }
  }

  static void _showError(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  static Future<void> _applyPlan(BuildContext context, DateTime date, Map<String, String> schedule, List<String> newActivities) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // 1. Create new activities
    if (newActivities.isNotEmpty) {
      final settingsRef = getFirestore().collection('user_settings').doc(uid);
       await getFirestore().runTransaction((tx) async {
        final doc = await tx.get(settingsRef);
        if (doc.exists) {
            final data = doc.data()!;
            final currentCustom = List<String>.from(data['customActivities'] ?? []);
            final currentArchived = List<String>.from(data['archivedActivities'] ?? []);
            for (final act in newActivities) {
                if (!currentCustom.contains(act)) currentCustom.add(act);
                if (currentArchived.contains(act)) currentArchived.remove(act);
            }
            tx.update(settingsRef, {
                'customActivities': currentCustom,
                'archivedActivities': currentArchived,
            });
        }
      });
    }

    // 2. Apply schedule to Timeline
    final entriesColl = getFirestore().collection('timeline_entries').doc(uid).collection('entries');
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    
    // Fetch existing entries for the day to update/merge
    final snap = await entriesColl.where('date', isEqualTo: dateStr).get();
    final existingMap = {
      for (var d in snap.docs) d.id: TimelineEntry.fromFirestore(d)
    };

    final batch = getFirestore().batch();

    for (final entry in schedule.entries) {
      final parts = entry.key.split(':');
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      // Normalize minute to 0 or 30
      final minute = m >= 30 ? 30 : 0;
      
      final start = DateTime(date.year, date.month, date.day, h, minute);
      final id = DateFormat('yyyyMMdd_HHmm').format(start);

      if (existingMap.containsKey(id)) {
        // Update existing
        // We only overwrite PLAN, or do we overwrite ACTUAL?
        // Context: "Planning my day". Usually implies "Plan" column.
        // But if I want to "Apply to my day's plan", it implies setting the Plan Activity.
        // Let's set Plan Activity.
        final existing = existingMap[id]!;
        final newData = {
          'planactivity': entry.value,
          // If actual is empty and it's future/now, maybe set actual too?
          // Let's stick to Plan Activity to be safe, user can check off later.
          // Or if user specifically asked to "Apply to plan", we set plan.
        };
        // Optional: If 'Sleep', maybe set both?
        batch.update(entriesColl.doc(id), newData);
      } else {
        // Create new
         final newEntry = TimelineEntry(
          id: id,
          userId: uid,
          date: date,
          startTime: start,
          endTime: start.add(Duration(minutes: minute==0?60:30)),
          planactivity: entry.value,
          planNotes: '',
          activity: '', // Leave actual empty for new plan items? Or maybe set it if it's "Sleep"?
          notes: '',
        );
        batch.set(entriesColl.doc(id), newEntry.toMap());
      }
    }

    await batch.commit();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan applied successfully!')));
    }
  }
}
