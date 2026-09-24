import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/task.dart';
import '../models/timeline_entry.dart';
import '../utils/task_quick_add.dart';
import '../utils/task_repeat.dart';
import '../utils/work_block_planner.dart';

/// Outcome of placing tasks into a day's work blocks.
class PlaceOutcome {
  final PlanResult result;
  final DateTime date;
  const PlaceOutcome(this.result, this.date);

  String summary() {
    final r = result;
    if (!r.hasWorkBlocks) {
      return 'No free work blocks on ${DateFormat('EEE d MMM').format(date)}. Apply a template with work blocks first.';
    }
    final parts = <String>[];
    if (r.placements.isNotEmpty) {
      parts.add('Placed ${r.placements.length}: ${r.placements.map((p) => '${p.task.title} @ ${DateFormat('H:mm').format(p.start)}').join(', ')}');
    }
    final short = r.placements.where((p) => p.minutes < p.task.estimatedMinutes).toList();
    if (short.isNotEmpty) {
      parts.add('${short.map((p) => p.task.title).join(', ')} got less time than estimated');
    }
    if (r.unplaced.isNotEmpty) {
      parts.add('No room for ${r.unplaced.map((t) => t.title).join(', ')}');
    }
    if (r.freeMinutesAfter > 0) {
      parts.add('${_h(r.freeMinutesAfter)} of work time still free');
    }
    return parts.join('. ');
  }

  static String _h(int min) => min % 60 == 0 ? '${min ~/ 60}h' : '${(min / 60).toStringAsFixed(1)}h';
}

/// Day-level planning: the tasks focused on a date, placing them into work
/// blocks, marking a day as planned, capturing open loops.
class DayPlanService {
  final FirebaseFirestore _db;
  DayPlanService({FirebaseFirestore? firestore}) : _db = firestore ?? getFirestore();

  static String dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  static DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  CollectionReference<Map<String, dynamic>> _timeline(String uid) =>
      _db.collection('timeline_entries').doc(uid).collection('entries');
  CollectionReference<Map<String, dynamic>> get _tasks => _db.collection('tasks');
  DocumentReference<Map<String, dynamic>> _dailyLog(String uid, DateTime date) =>
      _db.collection('daily_logs').doc(uid).collection('logs').doc(dateKey(date));

  Future<List<TimelineEntry>> loadEntries(String uid, DateTime date) async {
    final snap = await _timeline(uid).where('date', isEqualTo: dateKey(date)).get();
    final list = snap.docs.map((d) => TimelineEntry.fromMap(d.id, d.data())).toList();
    list.sort((a, b) => a.startTime.compareTo(b.startTime));
    return list;
  }

  static PlannerSlot toSlot(TimelineEntry e) => PlannerSlot(
        id: e.id,
        start: e.startTime,
        end: e.endTime,
        planactivity: e.planactivity,
        planNotes: e.planNotes,
        workBlock: e.workBlock,
        locked: e.locked,
        taskId: e.taskId,
      );

  /// Whether [date] has any non-sleep plan yet.
  static bool hasPlan(List<TimelineEntry> entries) =>
      entries.any((e) => e.planactivity.isNotEmpty && e.planactivity != 'Sleep');

  /// Places [tasks] (priority order) into [date]'s free work blocks and
  /// writes the result: slot `planNotes` = task title, `taskId` set, task
  /// `scheduledDate` = date. Slots that previously held one of these tasks
  /// are cleared first so re-running moves tasks rather than duplicating.
  Future<PlaceOutcome> placeTasks(
    String uid,
    DateTime date,
    List<Task> tasks, {
    DateTime? now,
    Map<String, String> folderActivities = const {},
  }) async {
    final entries = await loadEntries(uid, date);
    final n = now ?? DateTime.now();
    final isToday = dayOnly(date) == dayOnly(n);
    final result = WorkBlockPlanner.plan(
      slots: entries.map(toSlot).toList(),
      tasks: tasks.map((t) => PlannerTask(id: t.id, title: t.title, estimatedMinutes: t.estimatedMinutes)).toList(),
      notBefore: isToday ? n : null,
    );

    final batch = _db.batch();
    final taskIds = tasks.map((t) => t.id).toSet();
    final assigned = <String>{};
    for (final p in result.placements) {
      for (final s in p.slots) {
        assigned.add(s.id);
      }
    }
    // Release slots that held one of these tasks but are not assigned now.
    for (final e in entries) {
      if (e.taskId != null && taskIds.contains(e.taskId) && !assigned.contains(e.id)) {
        batch.set(_timeline(uid).doc(e.id), {'planNotes': '', 'taskId': FieldValue.delete()}, SetOptions(merge: true));
      }
    }
    for (final p in result.placements) {
      final task = tasks.firstWhere((t) => t.id == p.task.id);
      for (final s in p.slots) {
        final upd = <String, dynamic>{'planNotes': task.title, 'taskId': task.id};
        if (s.planactivity.isEmpty) {
          upd['planactivity'] = task.activity ?? folderActivities[task.folder] ?? 'Work';
        }
        batch.set(_timeline(uid).doc(s.id), upd, SetOptions(merge: true));
      }
      batch.set(
        _tasks.doc(task.id),
        {
          'scheduledDate': Timestamp.fromDate(p.start),
          'isToday': isToday,
        },
        SetOptions(merge: true),
      );
    }
    if (result.placements.isNotEmpty || entries.any((e) => e.taskId != null && taskIds.contains(e.taskId))) {
      await batch.commit();
    }
    return PlaceOutcome(result, date);
  }

  /// Sets the focus list for [date]: these tasks get `scheduledDate` = date
  /// (and `isToday` when date is today) and consecutive `sortOrder`; tasks
  /// previously scheduled on that day but no longer chosen are unscheduled.
  Future<void> setFocus(String uid, DateTime date, List<Task> chosen, List<Task> all, {DateTime? now}) async {
    final n = now ?? DateTime.now();
    final isToday = dayOnly(date) == dayOnly(n);
    final chosenIds = chosen.map((t) => t.id).toSet();
    final batch = _db.batch();
    for (var i = 0; i < chosen.length; i++) {
      batch.set(
        _tasks.doc(chosen[i].id),
        {
          'scheduledDate': Timestamp.fromDate(dayOnly(date)),
          'sortOrder': i,
          if (isToday) 'isToday': true,
        },
        SetOptions(merge: true),
      );
    }
    for (final t in all) {
      if (t.isCompleted || chosenIds.contains(t.id)) continue;
      if (t.scheduledDate != null && dayOnly(t.scheduledDate!) == dayOnly(date)) {
        batch.set(
          _tasks.doc(t.id),
          {'scheduledDate': null, if (isToday) 'isToday': false},
          SetOptions(merge: true),
        );
      }
    }
    await batch.commit();
  }

  Future<bool> isPlanned(String uid, DateTime date) async {
    final doc = await _dailyLog(uid, date).get();
    return doc.exists && doc.data()?['planned'] == true;
  }

  Future<void> markPlanned(String uid, DateTime date, {bool planned = true}) => _dailyLog(uid, date).set(
        {
          'date': dateKey(date),
          'planned': planned,
          'lastPlannedAt': Timestamp.fromDate(DateTime.now()),
        },
        SetOptions(merge: true),
      );

  /// Turns each non-empty line into an Inbox task (quick-add syntax
  /// supported). Returns the created titles.
  Future<List<String>> captureOpenLoops(
    String uid,
    String text, {
    required List<String> knownFolders,
    String? defaultFolder,
  }) async {
    final lines = text.split('\n').map((l) => l.trim().replaceFirst(RegExp(r'^[-*•]\s*'), '')).where((l) => l.isNotEmpty);
    final batch = _db.batch();
    final titles = <String>[];
    var i = 0;
    for (final line in lines) {
      final parsed = TaskQuickAdd.parse(line, knownFolders: knownFolders);
      final ref = _tasks.doc();
      final createdAt = DateTime.now().add(Duration(milliseconds: i++));
      final task = Task(
        id: ref.id,
        userId: uid,
        title: parsed.title,
        estimatedMinutes: parsed.estimatedMinutes ?? 30,
        createdAt: createdAt,
        folder: parsed.folder ?? defaultFolder,
        isToday: parsed.isToday,
        scheduledDate: parsed.scheduledDate,
      );
      batch.set(ref, task.toMap());
      titles.add(parsed.title);
    }
    if (titles.isNotEmpty) await batch.commit();
    return titles;
  }

  /// Creates the next occurrence of a repeating task that was just
  /// completed. Returns the new task id or null when nothing was created.
  Future<String?> rollRepeatingTask(Task task, {DateTime? completedOn}) async {
    if (!task.isRepeating) return null;
    final base = completedOn ?? DateTime.now();
    final anchor = task.scheduledDate != null && dayOnly(task.scheduledDate!).isAfter(dayOnly(base))
        ? task.scheduledDate!
        : base;
    final next = TaskRepeat.nextOccurrence(task.repeat, anchor);
    if (next == null) return null;
    // Avoid duplicates if the same occurrence already exists.
    final dup = await _tasks
        .where('userId', isEqualTo: task.userId)
        .where('title', isEqualTo: task.title)
        .where('isCompleted', isEqualTo: false)
        .get();
    for (final d in dup.docs) {
      final sd = (d.data()['scheduledDate'] as Timestamp?)?.toDate();
      if (sd != null && dayOnly(sd) == dayOnly(next)) return null;
    }
    final ref = _tasks.doc();
    final copy = Task(
      id: ref.id,
      userId: task.userId,
      title: task.title,
      notes: task.notes,
      estimatedMinutes: task.estimatedMinutes,
      createdAt: DateTime.now(),
      folder: task.folder,
      scheduledDate: next,
      activity: task.activity,
      repeat: task.repeat,
    );
    await ref.set(copy.toMap());
    return ref.id;
  }
}
