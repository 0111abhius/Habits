import 'package:cloud_firestore/cloud_firestore.dart';

import '../main.dart';
import '../models/habit.dart';
import '../utils/habit_stats.dart';

/// Firestore access for habits.
///
/// Layout:
/// - `habits/{uid}/habits/{habitId}`: the habit plus a denormalized
///   `history` map (`yyyy-MM-dd` -> value) used for streaks and dot grids.
/// - `habit_logs/{uid}/dates/{yyyy-MM-dd}/habits/{habitId}`: per-day log
///   documents (kept for analytics and backwards compatibility).
class HabitService {
  HabitService({FirebaseFirestore? firestore}) : _db = firestore ?? getFirestore();

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _habitsColl(String uid) =>
      _db.collection('habits').doc(uid).collection('habits');

  DocumentReference<Map<String, dynamic>> _logRef(String uid, String habitId, DateTime date) => _db
      .collection('habit_logs')
      .doc(uid)
      .collection('dates')
      .doc(HabitStats.dateKey(date))
      .collection('habits')
      .doc(habitId);

  Stream<List<Habit>> watchHabits(String uid) {
    return _habitsColl(uid).snapshots().map((snap) {
      final habits = snap.docs.map((d) => Habit.fromMap(d.id, d.data())).toList();
      habits.sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
      });
      return habits;
    });
  }

  Future<List<Habit>> fetchHabits(String uid) async {
    final snap = await _habitsColl(uid).get();
    final habits = snap.docs.map((d) => Habit.fromMap(d.id, d.data())).toList();
    habits.sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
    });
    return habits;
  }

  Future<Habit> addHabit({
    required String uid,
    required String name,
    required HabitType type,
    required HabitFrequency frequency,
    int weeklyTarget = 3,
    int targetCount = 1,
    String? reminderTime,
    int? sortOrder,
  }) async {
    final ref = _habitsColl(uid).doc();
    final habit = Habit(
      id: ref.id,
      name: name.trim(),
      type: type,
      frequency: frequency,
      weeklyTarget: weeklyTarget,
      targetCount: targetCount,
      userId: uid,
      createdAt: DateTime.now(),
      sortOrder: sortOrder ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      reminderTime: reminderTime,
    );
    await ref.set({...habit.toMap(), 'historyMigrated': true});
    return habit;
  }

  Future<void> updateHabit(String uid, Habit habit) async {
    final map = habit.toMap()..remove('history')..remove('completedDates')..remove('createdAt');
    await _habitsColl(uid).doc(habit.id).set(map, SetOptions(merge: true));
  }

  Future<void> setArchived(String uid, String habitId, bool archived) =>
      _habitsColl(uid).doc(habitId).set({'archived': archived}, SetOptions(merge: true));

  Future<void> deleteHabit(String uid, String habitId) => _habitsColl(uid).doc(habitId).delete();

  Future<void> saveOrder(String uid, List<Habit> ordered) async {
    final batch = _db.batch();
    for (int i = 0; i < ordered.length; i++) {
      batch.set(_habitsColl(uid).doc(ordered[i].id), {'sortOrder': i}, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// Records [value] for [habit] on [date]. Binary habits use 1/0.
  Future<void> setValue(String uid, Habit habit, DateTime date, int value) async {
    final key = HabitStats.dateKey(date);
    final clamped = value < 0 ? 0 : value;
    final batch = _db.batch();
    final dynamic logValue = habit.type == HabitType.binary ? clamped > 0 : clamped;
    batch.set(_logRef(uid, habit.id, date), {'value': logValue}, SetOptions(merge: true));
    batch.set(
      _habitsColl(uid).doc(habit.id),
      {
        'history': {key: clamped}
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> toggle(String uid, Habit habit, DateTime date) {
    final done = HabitStats.isDoneOn(habit, date);
    return setValue(uid, habit, date, done ? 0 : 1);
  }

  Future<void> increment(String uid, Habit habit, DateTime date, {int by = 1}) {
    final current = HabitStats.valueOn(habit, date);
    return setValue(uid, habit, date, current + by);
  }

  /// One-time migration: habits created before `history` existed have their
  /// last [days] days of `habit_logs` copied into the denormalized map.
  Future<void> backfillHistoryIfNeeded(String uid, List<Habit> habits, {int days = 90}) async {
    final snap = await _habitsColl(uid).get();
    final pending = <String>{};
    for (final d in snap.docs) {
      if (d.data()['historyMigrated'] != true) pending.add(d.id);
    }
    if (pending.isEmpty) return;

    final today = HabitStats.dayOnly(DateTime.now());
    final Map<String, Map<String, int>> collected = {for (final id in pending) id: {}};
    for (int i = 0; i < days; i++) {
      final date = today.subtract(Duration(days: i));
      final dayColl = _db
          .collection('habit_logs')
          .doc(uid)
          .collection('dates')
          .doc(HabitStats.dateKey(date))
          .collection('habits');
      final logs = await dayColl.get();
      for (final doc in logs.docs) {
        if (!pending.contains(doc.id)) continue;
        final v = doc.data()['value'];
        int intVal = 0;
        if (v is bool) intVal = v ? 1 : 0;
        if (v is num) intVal = v.toInt();
        if (intVal > 0) collected[doc.id]![HabitStats.dateKey(date)] = intVal;
      }
    }

    final batch = _db.batch();
    collected.forEach((id, history) {
      batch.set(
        _habitsColl(uid).doc(id),
        {'history': history, 'historyMigrated': true},
        SetOptions(merge: true),
      );
    });
    await batch.commit();
  }
}
