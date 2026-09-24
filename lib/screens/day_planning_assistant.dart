import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:intl/intl.dart';
import 'dart:convert';
import '../models/timeline_entry.dart';
import '../models/task.dart';
import '../models/user_settings.dart';
import '../models/ai_proposal.dart';
import '../utils/ai_service.dart';
import '../widgets/ai_planning_dialogs.dart';
import '../main.dart'; // for getFirestore()

class DayPlanningAssistant {
  static Future<Map<String, AIProposal>?> show(BuildContext context, DateTime date, List<TimelineEntry> currentEntries, List<String> availableActivities, {Function(bool)? onLoading}) async {
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

    // NEW LOGIC: If planning for Today, ensure we start from "Now" (rounded up to next 30 min)
    // to avoid re-planning the past.
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) {
       final currentMins = now.hour * 60 + now.minute;
       // Round up to next 30 minute block logic:
       // If currently 10:05 -> 10:30
       // If currently 10:35 -> 11:00
       // If currently 10:00 -> 10:00 (or should it be 10:30? Let's say 10:00 is fine if we are quick, but effectively 10:00 is "now")
       
       int nextBlock = (currentMins / 30).ceil() * 30;
       // If we are essentially "at" the block boundary (within 1 min?), maybe valid. 
       // But simpler to just use ceil. 
       // Note: if exactly 10:30, ceil gives 10:30.
       
       final wakeMins = wakeTime.hour * 60 + wakeTime.minute;
       if (nextBlock > wakeMins) {
          // Check if we passed sleep time?
          final sleepMins = sleepTime.hour * 60 + sleepTime.minute;
          // Normal wake < sleep case
          if (sleepMins > wakeMins && nextBlock >= sleepMins) {
             // It's effectively end of day.
             // We can clamp to sleepTime or just let it be. 
             // If we set wakeTime = sleepTime, activeDuration = 0.
             wakeTime = sleepTime;
          } else {
             // Handle midnight crossing if needed? (sleep < wake)
             // The app seems to assume Day view 7am - 11pm usually. 
             // Let's assume standard day for "Today" planning.
             
             final h = nextBlock ~/ 60;
             final m = nextBlock % 60;
             if (h < 24) {
               wakeTime = TimeOfDay(hour: h, minute: m);
             } else {
                // Technically tomorrow.
                wakeTime = const TimeOfDay(hour: 23, minute: 59);
             }
          }
       }
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
    // 2. Logic Fork
    if (isFull && defaultGoal.isNotEmpty) {
        // Auto-Feedback Path
        onLoading?.call(true);
        final wStr = '${wakeTime.hour.toString().padLeft(2,'0')}:${wakeTime.minute.toString().padLeft(2,'0')}';
        final sStr = '${sleepTime.hour.toString().padLeft(2,'0')}:${sleepTime.minute.toString().padLeft(2,'0')}';
        final result = await _showFeedbackDialog(context, date, currentEntries, availableActivities, defaultGoal, isAuto: true, onLoading: onLoading, wakeTime: wStr, sleepTime: sStr);
        onLoading?.call(false);
        return result;
    } else {
        // Standard Path
        final result = await AIGoalDialog.show(
          context, 
          title: 'AI Day Planner', 
          promptLabel: 'Planning for ${DateFormat('MMM d').format(date)}.\nWhat is your main goal?',
          initialGoal: defaultGoal,
        );

        if (result != null) {
           onLoading?.call(true);
           final wStr = '${wakeTime.hour.toString().padLeft(2,'0')}:${wakeTime.minute.toString().padLeft(2,'0')}';
           final sStr = '${sleepTime.hour.toString().padLeft(2,'0')}:${sleepTime.minute.toString().padLeft(2,'0')}';
           Map<String, AIProposal>? aiRes;
           if (isFull) {
               aiRes = await _showFeedbackDialog(context, date, currentEntries, availableActivities, result.goal, isAuto: false, onLoading: onLoading, wakeTime: wStr, sleepTime: sStr);
           } else {
               aiRes = await _generatePlan(
                 context, 
                 date, 
                 currentEntries, 
                 availableActivities, 
                 result.goal, 
                 onLoading: onLoading, 
                 wakeTime: wStr, 
                 sleepTime: sStr,
                 includeOverdue: result.includeOverdue,
                 includeToday: result.includeToday,
                 includeUnscheduled: result.includeUnscheduled,
               );
           }
           onLoading?.call(false);
           return aiRes;
        }
    }
    return null;
  }

  static Future<Map<String, AIProposal>?> _showFeedbackDialog(BuildContext context, DateTime date, List<TimelineEntry> entries, List<String> activities, String goal, {required bool isAuto, Function(bool)? onLoading, required String wakeTime, required String sleepTime}) async {
      // No blocking dialog here, rely on caller or callback
      // But we need to await the AI service. The caller (show) already set loading=true.
      
      final currentPlan = _serializePlan(entries, []);
      final ai = AIService();
      final jsonResponse = await ai.getPlanFeedback(currentPlan: currentPlan, goal: goal);
      
      if (!context.mounted) return null;

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

      return await showDialog<bool>(
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
              onPressed: () => Navigator.pop(ctx, false),
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
             onLoading?.call(false); // Stop spinning while user reviews feedback
             
             final result = await AIGoalDialog.show(
                context, 
                title: 'Refine Goal', 
                promptLabel: 'Edit your goal or context for replanning:',
                initialGoal: goal,
             );
             
             if (result != null) {
                 onLoading?.call(true); // Restart spinning
                 return await _generatePlan(
                   context, 
                   date, 
                   entries, 
                   activities, 
                   result.goal, 
                   onLoading: onLoading, 
                   wakeTime: wakeTime, 
                   sleepTime: sleepTime,
                   includeOverdue: result.includeOverdue,
                   includeToday: result.includeToday,
                   includeUnscheduled: result.includeUnscheduled,
                 );
             }
         }
         return null;
      });
  }

  static String _serializePlan(List<TimelineEntry> entries, List<dynamic> tasks) {
      final buffer = StringBuffer();
      entries.sort((a,b)=>a.startTime.compareTo(b.startTime));
      for (final e in entries) {
        final time = DateFormat('HH:mm').format(e.startTime);
        final act = e.planactivity.isNotEmpty ? e.planactivity : e.activity;
        if (act.isNotEmpty) {
           buffer.writeln('$time - $act');
        }
      }
      return buffer.toString().isEmpty ? '(No activities planned yet)' : buffer.toString();
  }

  static Future<Map<String, AIProposal>?> _generatePlan(BuildContext context, DateTime date, List<TimelineEntry> entries, List<String> activities, String goal, {Function(bool)? onLoading, required String wakeTime, required String sleepTime, bool includeOverdue = true, bool includeToday = true, bool includeUnscheduled = true}) async {
    print("DEBUG: _generatePlan called");
    final Set<String> knownTaskTitles = {};
    final Map<String, String> taskToActivityMap = {}; // Maps Task Title -> Activity Name
    
    try {
      // Serialize current plan
      final buffer = StringBuffer();
      // sort entries
      entries.sort((a,b)=>a.startTime.compareTo(b.startTime));

      for (final e in entries) {
        final time = DateFormat('HH:mm').format(e.startTime);
        final act = e.planactivity.isNotEmpty ? e.planactivity : e.activity;
        if (act.isNotEmpty) {
           buffer.writeln('$time - $act');
        }
      }
      
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
        
        // Sorting Logic... same as previous
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);
        
        final List<Task> highPriority = [];
        final List<Task> otherTasks = [];

        for (final t in allTasks) {
           bool isOverdue = false;
           // If manually flagged as Today, respect that even if scheduledDate is null
           bool isToday = t.isToday; 
           bool isFuture = false;
           
           if (t.scheduledDate != null) {
               final d = DateTime(t.scheduledDate!.year, t.scheduledDate!.month, t.scheduledDate!.day);
               if (d.isBefore(todayStart)) isOverdue = true;
               if (d == todayStart) isToday = true;
               if (d.isAfter(todayStart)) isFuture = true;
           }
           
           // If it isToday, it is NOT Unscheduled effectively.
           bool isUnscheduled = t.scheduledDate == null && !isToday;

           // Filter based on flags
           // Always exclude future tasks
           if (isFuture) {
             print("DEBUG: Task '${t.title}' SKIPPED (Future)");
             continue;
           }

           if (isOverdue && !includeOverdue) {
             print("DEBUG: Task '${t.title}' SKIPPED (Overdue excluded)");
             continue;
           }
           if (isToday && !includeToday) {
             print("DEBUG: Task '${t.title}' SKIPPED (Today excluded)");
             continue;
           }
           if (isUnscheduled && !includeUnscheduled) {
             print("DEBUG: Task '${t.title}' SKIPPED (Unscheduled excluded)");
             continue; 
           }
           
           print("DEBUG: Task '${t.title}' KEPT. (Overdue:$isOverdue, Today:$isToday, Unscheduled:$isUnscheduled)");

           if (isOverdue || isToday) highPriority.add(t);
           else otherTasks.add(t);
        }

        if (highPriority.isNotEmpty) {
           buffer.writeln('\nURGENT / TODAY TITLES:');
           for (final t in highPriority) {
              final due = t.scheduledDate != null && t.scheduledDate!.isBefore(todayStart) ? ' [OVERDUE]' : '';
              final actInfo = (t.activity != null && t.activity!.isNotEmpty) ? ' [Activity: ${t.activity}]' : '';
              buffer.writeln('- ${t.title} (${t.estimatedMinutes}m)$due$actInfo');
              knownTaskTitles.add(t.title);
              if (t.activity != null && t.activity!.isNotEmpty) {
                 taskToActivityMap[t.title] = t.activity!;
              }
           }
        }
        if (otherTasks.isNotEmpty) {
           buffer.writeln('\nOTHER AVAILABLE TASKS (Select if relevant to goal):');
           for (final t in otherTasks.take(15)) {
              final actInfo = (t.activity != null && t.activity!.isNotEmpty) ? ' [Activity: ${t.activity}]' : '';
              buffer.writeln('- ${t.title} (${t.estimatedMinutes}m)$actInfo');
              knownTaskTitles.add(t.title);
              if (t.activity != null && t.activity!.isNotEmpty) {
                 taskToActivityMap[t.title] = t.activity!;
              }
           }
        }
      }

      final currentPlan = buffer.toString().isEmpty ? '(No activities planned yet)' : buffer.toString();

      final ai = AIService();
      final jsonStr = await ai.getDayPlanSuggestions(
        currentPlan: currentPlan,
        goal: goal.isEmpty ? 'Productivity' : goal,
        existingActivities: activities,
        wakeTime: wakeTime,
        sleepTime: sleepTime,
      );

      print("DEBUG: AI Raw Response: $jsonStr");
      
      if (!context.mounted) return null;
      onLoading?.call(false); 
      
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (data.containsKey('error')) {
        _showError(context, 'AI Error: ${data['error']}');
        return null;
      }

      data['newActivities'] = AIService.detectNewActivities(data, activities);

      // Parse schedule
      final Map<String, dynamic> rawSchedule = data['schedule'] ?? {};
      final Map<String, AIProposal> finalSchedule = {};
      
      rawSchedule.forEach((key, val) {
          if (val is String) {
             // Backward compat or simple structure
             finalSchedule[key] = AIProposal(activity: val, reason: '', isTask: false);
          } else if (val is Map) {
             var act = val['activity']?.toString() ?? '';
             final reason = val['reason']?.toString() ?? '';
             final tTitle = val['taskTitle']?.toString();
             
             if (act.isNotEmpty) {
                // Check if this corresponds to a task
                // 1. Explicit taskTitle returned by AI
                // 2. Or fallback: 'reason' might be the task title (legacy)
                
                String? finalTaskTitle = tTitle;
                bool isTask = false;
                
                // Correction Logic:
                // If the 'activity' matches a known Task Title, it means AI put Title in Activity.
                if (knownTaskTitles.contains(act)) {
                    isTask = true;
                    finalTaskTitle = act; // The "Activity" field IS the task title here
                    // Try to restore the real activity if we have it
                    if (taskToActivityMap.containsKey(act)) {
                        act = taskToActivityMap[act]!;
                    } else {
                        // Fallback: If we don't have a mapped activity, checks if we can infer or leave it specific?
                        // If the task title IS the activity (e.g. "Jogging"), it's fine.
                        // But usually tasks are "Finish Report".
                        // If we can't find activity, we might default to "Work" or just keep the Title.
                        // Let's keep the Title if no mapping found, it's safer than guessing.
                    }
                } else if (finalTaskTitle != null && knownTaskTitles.contains(finalTaskTitle)) {
                   isTask = true;
                   // Use map to ensure correct activity if available
                   if (taskToActivityMap.containsKey(finalTaskTitle)) {
                      // Only override if the AI suggested something seemingly generic or wrong?
                      // The prompt instructions say: "Set activity field to 'Name' (e.g. 'Work')"
                      // If AI followed instructions, 'act' is 'Work'. 
                      // If we have a stronger binding in our map, we SHOULD prefer the map.
                      // E.g. Task "Math" [Activity: Study]. AI says Activity: "Study". Map says "Study". Matches.
                      // AI says Activity: "Work". Map says "Study". We should probably correct it to "Study".
                      act = taskToActivityMap[finalTaskTitle]!;
                   }
                } else if (knownTaskTitles.contains(reason)) {
                   isTask = true;
                   finalTaskTitle = reason; // Legacy fallback
                   if (taskToActivityMap.containsKey(finalTaskTitle)) {
                       act = taskToActivityMap[finalTaskTitle]!;
                   }
                }

                finalSchedule[key] = AIProposal(
                   activity: act, 
                   reason: reason, 
                   isTask: isTask,
                   taskTitle: finalTaskTitle
                );
             }
          }
      });
      
      // INTERPOLATION LOGIC
      final List<String> sortedKeys = finalSchedule.keys.toList()..sort();
      if (sortedKeys.isNotEmpty) {
         for (int i = 0; i < sortedKeys.length - 1; i++) {
            final currTime = sortedKeys[i];
            final nextTime = sortedKeys[i+1];
            
            final h1 = int.parse(currTime.split(':')[0]);
            final m1 = int.parse(currTime.split(':')[1]);
            final t1 = h1 * 60 + m1;
            
            final h2 = int.parse(nextTime.split(':')[0]);
            final m2 = int.parse(nextTime.split(':')[1]);
            final t2 = h2 * 60 + m2;
            
            // Fill ALL 30-minute slots between t1 and t2 with the activity from t1
            int cursor = t1 + 30; 
            while (cursor < t2) {
               final cH = cursor ~/ 60;
               final cM = cursor % 60;
               final cKey = '${cH.toString().padLeft(2,'0')}:${cM.toString().padLeft(2,'0')}';
               
               if (!finalSchedule.containsKey(cKey)) {
                  final prevProp = finalSchedule[currTime]!;
                  finalSchedule[cKey] = AIProposal(
                    activity: prevProp.activity,
                    reason: prevProp.reason,
                    isTask: prevProp.isTask,
                    taskTitle: prevProp.taskTitle,
                  );
               }
               cursor += 30;
            }
         }
      }
      
      final List<String> newActs = List<String>.from(data['newActivities'] ?? []);
      if (newActs.isNotEmpty) {
          await _createNewActivities(context, newActs);
      }

      return finalSchedule;

    } catch (e) {
      if (context.mounted) {
        onLoading?.call(false);
        _showError(context, 'Error: $e');
      }
      return null;
    }
  }

  static Future<void> _createNewActivities(BuildContext context, List<String> newActivities) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
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
