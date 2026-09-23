import '../models/habit.dart';

/// Pure helpers for reasoning about habit completion from [Habit.history].
///
/// All dates are treated as local calendar days; time components are ignored.
class HabitStats {
  HabitStats._();

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Monday of the week containing [d].
  static DateTime weekStart(DateTime d) {
    final day = dayOnly(d);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  /// Raw value logged on [date] (0 when nothing logged).
  static int valueOn(Habit habit, DateTime date) => habit.history[dateKey(date)] ?? 0;

  /// Whether the habit counts as completed on [date].
  static bool isDoneOn(Habit habit, DateTime date) {
    final v = valueOn(habit, date);
    return habit.type == HabitType.binary ? v > 0 : v >= habit.targetCount;
  }

  /// Number of completed days in the Mon-Sun week containing [date].
  static int completionsInWeek(Habit habit, DateTime date) {
    final start = weekStart(date);
    int n = 0;
    for (int i = 0; i < 7; i++) {
      if (isDoneOn(habit, start.add(Duration(days: i)))) n++;
    }
    return n;
  }

  /// Whether the week containing [date] met its target (weekly habits only).
  static bool weekMet(Habit habit, DateTime date) =>
      completionsInWeek(habit, date) >= habit.weeklyTarget;

  /// Current streak as of [today].
  ///
  /// Daily habits: consecutive completed days ending today, or ending
  /// yesterday if today is not (yet) done — today never breaks a streak.
  /// Weekly habits: consecutive weeks meeting the target; the current week
  /// counts if already met and does not break the streak while in progress.
  static int currentStreak(Habit habit, DateTime today) {
    final day = dayOnly(today);
    if (habit.frequency == HabitFrequency.weekly) {
      int streak = 0;
      DateTime cursor = weekStart(day);
      if (weekMet(habit, cursor)) {
        streak++;
      }
      cursor = cursor.subtract(const Duration(days: 7));
      // Guard against unbounded loops on pathological data.
      for (int i = 0; i < 520; i++) {
        if (!weekMet(habit, cursor)) break;
        streak++;
        cursor = cursor.subtract(const Duration(days: 7));
      }
      return streak;
    }

    int streak = 0;
    DateTime cursor = day;
    if (!isDoneOn(habit, cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    for (int i = 0; i < 3660; i++) {
      if (!isDoneOn(habit, cursor)) break;
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Longest streak ever recorded (in days for daily habits, weeks for
  /// weekly habits).
  static int bestStreak(Habit habit) {
    if (habit.history.isEmpty) return 0;
    final keys = habit.history.keys.toList()..sort();
    final first = DateTime.parse(keys.first);
    final last = DateTime.parse(keys.last);

    if (habit.frequency == HabitFrequency.weekly) {
      int best = 0, run = 0;
      DateTime cursor = weekStart(first);
      final end = weekStart(last);
      while (!cursor.isAfter(end)) {
        if (weekMet(habit, cursor)) {
          run++;
          if (run > best) best = run;
        } else {
          run = 0;
        }
        cursor = cursor.add(const Duration(days: 7));
      }
      return best;
    }

    int best = 0, run = 0;
    DateTime cursor = dayOnly(first);
    final end = dayOnly(last);
    while (!cursor.isAfter(end)) {
      if (isDoneOn(habit, cursor)) {
        run++;
        if (run > best) best = run;
      } else {
        run = 0;
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return best;
  }

  /// Fraction of the last [days] days (ending [today]) that were completed.
  static double completionRate(Habit habit, DateTime today, {int days = 30}) {
    if (days <= 0) return 0;
    final day = dayOnly(today);
    final created = dayOnly(habit.createdAt);
    int done = 0, considered = 0;
    for (int i = 0; i < days; i++) {
      final d = day.subtract(Duration(days: i));
      if (d.isBefore(created)) break;
      considered++;
      if (isDoneOn(habit, d)) done++;
    }
    if (considered == 0) return 0;
    return done / considered;
  }

  /// Total number of completed days ever.
  static int totalCompletions(Habit habit) {
    int n = 0;
    habit.history.forEach((k, v) {
      final done = habit.type == HabitType.binary ? v > 0 : v >= habit.targetCount;
      if (done) n++;
    });
    return n;
  }

  /// The last [count] days ending with [today], oldest first.
  static List<DateTime> lastDays(DateTime today, int count) {
    final day = dayOnly(today);
    return List.generate(count, (i) => day.subtract(Duration(days: count - 1 - i)));
  }

  /// Whether the habit is "due" on [date]: daily habits always are; weekly
  /// habits are due while the week's target has not been met yet.
  static bool isDueOn(Habit habit, DateTime date) {
    if (habit.frequency == HabitFrequency.daily) return true;
    return !weekMet(habit, date) || isDoneOn(habit, date);
  }
}
