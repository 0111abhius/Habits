import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../models/timeline_entry.dart';
import '../utils/ai_service.dart';
import '../widgets/ai_planning_dialogs.dart';
import '../main.dart'; // for getFirestore()

class DayPlanningAssistant {
  static Future<void> show(BuildContext context, DateTime date, List<TimelineEntry> currentEntries, List<String> availableActivities) async {
    final goal = await AIGoalDialog.show(
      context, 
      title: 'AI Day Planner', 
      promptLabel: 'Planning for ${DateFormat('MMM d').format(date)}.\nWhat is your main goal?',
    );

    if (goal != null) {
      _generatePlan(context, date, currentEntries, availableActivities, goal);
    }
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
      for (final e in entries) {
        final time = DateFormat('HH:mm').format(e.startTime);
        final act = e.planactivity.isNotEmpty ? e.planactivity : e.activity;
        if (act.isNotEmpty) {
           buffer.writeln('$time - $act');
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

        AIPlanReviewDialog.show(context, data, (schedule, newActivities) {
             _applyPlan(context, date, schedule, newActivities);
        });

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
