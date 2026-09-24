import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/habit.dart';
import '../models/user_settings.dart';
import '../utils/habit_stats.dart';
import 'habit_service.dart';
import 'notification_bridge_stub.dart' if (dart.library.js_interop) 'notification_bridge_web.dart';

/// A reminder that is due right now.
class DueReminder {
  final String id;
  final String title;
  final String body;
  const DueReminder({required this.id, required this.title, required this.body});
}

/// Schedules browser notifications while the web app is open (including as an
/// installed PWA). Reminders:
/// - "Plan tomorrow" at [UserSettings.planTomorrowReminderTime] if tomorrow
///   is not planned yet (the evening shutdown anchor)
/// - "Plan your day" at [UserSettings.planReminderTime] if nothing is planned
///   (morning fallback)
/// - "Log your day" at [UserSettings.logReminderTime] if the day isn't logged
/// - per-habit reminders at [Habit.reminderTime] when the habit isn't done
///
/// Firing is idempotent per day using localStorage so reloading the tab does
/// not repeat a notification.
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  Timer? _timer;
  String? _uid;
  StreamSubscription? _settingsSub;
  UserSettings? _settings;
  final Set<String> _firedInMemory = {};

  /// In-app fallback: screens can listen and show a banner/snackbar.
  final ValueNotifier<DueReminder?> lastFired = ValueNotifier(null);

  static bool get isSupported => NotificationBridge.isSupported;
  static String get permission => NotificationBridge.permission;
  static Future<String> requestPermission() => NotificationBridge.requestPermission();

  static void showTest() {
    NotificationBridge.show('Day Coach', body: 'Reminders are working.', tag: 'test');
  }

  void start(String uid) {
    if (_uid == uid && _timer != null) return;
    stop();
    _uid = uid;
    _settingsSub = getFirestore().collection('user_settings').doc(uid).snapshots().listen((doc) {
      if (doc.exists && doc.data() != null) {
        _settings = UserSettings.fromMap(doc.data()!);
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => tick(DateTime.now()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _settingsSub?.cancel();
    _settingsSub = null;
    _uid = null;
    _settings = null;
  }

  static String _key(String id, DateTime now) => 'reminder_${DateFormat('yyyy-MM-dd').format(now)}_$id';

  bool _alreadyFired(String id, DateTime now) {
    final k = _key(id, now);
    if (_firedInMemory.contains(k)) return true;
    return NotificationBridge.localGet(k) == '1';
  }

  void _markFired(String id, DateTime now) {
    final k = _key(id, now);
    _firedInMemory.add(k);
    NotificationBridge.localSet(k, '1');
  }

  /// Returns true when [now] is within the 5-minute window after [t].
  static bool isWithinWindow(TimeOfDay t, DateTime now, {int windowMinutes = 5}) {
    final target = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    final diff = now.difference(target).inMinutes;
    return diff >= 0 && diff < windowMinutes;
  }

  Future<void> tick(DateTime now) async {
    final uid = _uid;
    final settings = _settings;
    if (uid == null || settings == null || !settings.remindersEnabled) return;
    if (NotificationBridge.permission != 'granted') return;

    final due = await computeDue(uid: uid, settings: settings, now: now);
    for (final r in due) {
      if (_alreadyFired(r.id, now)) continue;
      _markFired(r.id, now);
      NotificationBridge.show(r.title, body: r.body, tag: r.id);
      lastFired.value = r;
    }
  }

  /// Pure-ish evaluation of what should fire at [now]; reads Firestore for
  /// today's state.
  Future<List<DueReminder>> computeDue({
    required String uid,
    required UserSettings settings,
    required DateTime now,
    HabitService? habitService,
  }) async {
    final due = <DueReminder>[];
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    if (isWithinWindow(settings.planReminderTime, now) && !_alreadyFired('plan', now)) {
      final planned = await getFirestore()
          .collection('timeline_entries')
          .doc(uid)
          .collection('entries')
          .where('date', isEqualTo: todayStr)
          .get();
      final hasPlan = planned.docs.any((d) {
        final p = d.data()['planactivity'];
        return p is String && p.isNotEmpty && p != 'Sleep';
      });
      if (!hasPlan) {
        due.add(const DueReminder(
          id: 'plan',
          title: 'Plan your day',
          body: 'Two minutes now saves the afternoon. Sketch your day or ask AI to draft it.',
        ));
      }
    }

    if (isWithinWindow(settings.planTomorrowReminderTime, now) && !_alreadyFired('plan_tomorrow', now)) {
      final tomorrow = now.add(const Duration(days: 1));
      final tomorrowStr = DateFormat('yyyy-MM-dd').format(tomorrow);
      final log = await getFirestore().collection('daily_logs').doc(uid).collection('logs').doc(tomorrowStr).get();
      final planned = log.exists && log.data()?['planned'] == true;
      if (!planned) {
        due.add(const DueReminder(
          id: 'plan_tomorrow',
          title: 'Shutdown: plan tomorrow',
          body: 'Pick tomorrow\'s top 3 and dump the open loops. Arrive home with work parked.',
        ));
      }
    }

    if (isWithinWindow(settings.logReminderTime, now) && !_alreadyFired('log', now)) {
      final log = await getFirestore().collection('daily_logs').doc(uid).collection('logs').doc(todayStr).get();
      final complete = log.exists && log.data()?['complete'] == true;
      if (!complete) {
        due.add(const DueReminder(
          id: 'log',
          title: 'How did today go?',
          body: 'Log your day and tick off your habits to keep the streak going.',
        ));
      }
    }

    // Habit reminders: only fetch when at least one could be due this minute.
    List<Habit>? habits;
    try {
      habits = await (habitService ?? HabitService()).fetchHabits(uid);
    } catch (_) {
      habits = null;
    }
    if (habits != null) {
      for (final h in habits) {
        if (h.archived || h.reminderTime == null) continue;
        final t = UserSettings.tryParseTime(h.reminderTime);
        if (t == null || !isWithinWindow(t, now)) continue;
        if (_alreadyFired('habit_${h.id}', now)) continue;
        if (HabitStats.isDoneOn(h, now) || !HabitStats.isDueOn(h, now)) continue;
        final streak = HabitStats.currentStreak(h, now);
        due.add(DueReminder(
          id: 'habit_${h.id}',
          title: h.name,
          body: streak > 0 ? 'Keep your $streak-day streak alive.' : 'Time for ${h.name.toLowerCase()}.',
        ));
      }
    }

    return due;
  }

  /// Persists reminder preferences.
  static Future<void> saveSettings(String uid,
      {required bool enabled, required TimeOfDay planTime, required TimeOfDay logTime, TimeOfDay? planTomorrowTime}) {
    return getFirestore().collection('user_settings').doc(uid).set({
      'remindersEnabled': enabled,
      'planReminderTime': UserSettings.fmt(planTime),
      'logReminderTime': UserSettings.fmt(logTime),
      if (planTomorrowTime != null) 'planTomorrowReminderTime': UserSettings.fmt(planTomorrowTime),
    }, SetOptions(merge: true));
  }
}
