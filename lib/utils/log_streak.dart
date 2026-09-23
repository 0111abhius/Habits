import 'package:intl/intl.dart';

/// Consecutive days marked as logged (keys are `yyyy-MM-dd`) ending today, or
/// yesterday if today is not finished yet — today never breaks the streak.
int computeLogStreak(Set<String> loggedDates, DateTime today) {
  DateTime cursor = DateTime(today.year, today.month, today.day);
  String key(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  if (!loggedDates.contains(key(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  int streak = 0;
  while (loggedDates.contains(key(cursor)) && streak < 10000) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}
