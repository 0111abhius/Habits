import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/models/habit.dart';
import 'package:habit_logger/utils/habit_stats.dart';

Habit _habit({
  HabitType type = HabitType.binary,
  HabitFrequency frequency = HabitFrequency.daily,
  int weeklyTarget = 3,
  int targetCount = 1,
  Map<String, int> history = const {},
  DateTime? createdAt,
}) {
  return Habit(
    id: 'h',
    name: 'Test',
    type: type,
    frequency: frequency,
    weeklyTarget: weeklyTarget,
    targetCount: targetCount,
    userId: 'u',
    createdAt: createdAt ?? DateTime(2024, 1, 1),
    history: history,
  );
}

void main() {
  // Wednesday 2024-06-12.
  final today = DateTime(2024, 6, 12, 15, 30);

  group('HabitStats basics', () {
    test('dateKey pads and weekStart returns Monday', () {
      expect(HabitStats.dateKey(DateTime(2024, 3, 5)), '2024-03-05');
      expect(HabitStats.weekStart(today), DateTime(2024, 6, 10));
      expect(HabitStats.weekStart(DateTime(2024, 6, 10)), DateTime(2024, 6, 10));
      expect(HabitStats.weekStart(DateTime(2024, 6, 16)), DateTime(2024, 6, 10));
    });

    test('lastDays is oldest-first and ends today', () {
      final days = HabitStats.lastDays(today, 3);
      expect(days, [DateTime(2024, 6, 10), DateTime(2024, 6, 11), DateTime(2024, 6, 12)]);
    });

    test('counter habits are done only when target reached', () {
      final h = _habit(type: HabitType.counter, targetCount: 3, history: {
        '2024-06-11': 2,
        '2024-06-12': 3,
      });
      expect(HabitStats.isDoneOn(h, DateTime(2024, 6, 11)), isFalse);
      expect(HabitStats.isDoneOn(h, DateTime(2024, 6, 12)), isTrue);
      expect(HabitStats.valueOn(h, DateTime(2024, 6, 10)), 0);
      expect(HabitStats.totalCompletions(h), 1);
    });
  });

  group('daily streaks', () {
    test('counts consecutive days ending today', () {
      final h = _habit(history: {
        '2024-06-10': 1,
        '2024-06-11': 1,
        '2024-06-12': 1,
      });
      expect(HabitStats.currentStreak(h, today), 3);
    });

    test('today not done yet does not break the streak', () {
      final h = _habit(history: {
        '2024-06-09': 1,
        '2024-06-10': 1,
        '2024-06-11': 1,
      });
      expect(HabitStats.currentStreak(h, today), 3);
    });

    test('a missed day before yesterday resets the streak', () {
      final h = _habit(history: {
        '2024-06-08': 1,
        '2024-06-09': 1,
        '2024-06-11': 1,
        '2024-06-12': 1,
      });
      expect(HabitStats.currentStreak(h, today), 2);
    });

    test('empty history has zero streak', () {
      expect(HabitStats.currentStreak(_habit(), today), 0);
      expect(HabitStats.bestStreak(_habit()), 0);
    });

    test('bestStreak finds the longest historical run', () {
      final h = _habit(history: {
        '2024-05-01': 1,
        '2024-05-02': 1,
        '2024-05-03': 1,
        '2024-05-04': 1,
        '2024-05-10': 1,
        '2024-06-12': 1,
      });
      expect(HabitStats.bestStreak(h), 4);
    });

    test('completionRate ignores days before creation', () {
      final h = _habit(
        createdAt: DateTime(2024, 6, 9),
        history: {'2024-06-10': 1, '2024-06-12': 1},
      );
      // Considered: 9, 10, 11, 12 -> 2/4.
      expect(HabitStats.completionRate(h, today, days: 30), closeTo(0.5, 1e-9));
      expect(HabitStats.completionRate(h, today, days: 0), 0);
    });
  });

  group('weekly habits', () {
    test('completionsInWeek and weekMet', () {
      final h = _habit(frequency: HabitFrequency.weekly, weeklyTarget: 3, history: {
        '2024-06-10': 1,
        '2024-06-11': 1,
      });
      expect(HabitStats.completionsInWeek(h, today), 2);
      expect(HabitStats.weekMet(h, today), isFalse);
      expect(HabitStats.isDueOn(h, today), isTrue);

      final done = _habit(frequency: HabitFrequency.weekly, weeklyTarget: 2, history: {
        '2024-06-10': 1,
        '2024-06-11': 1,
      });
      expect(HabitStats.weekMet(done, today), isTrue);
      // Target met and today not logged -> no longer due.
      expect(HabitStats.isDueOn(done, today), isFalse);
      // But a day that was logged stays "due" so it renders as done.
      expect(HabitStats.isDueOn(done, DateTime(2024, 6, 11)), isTrue);
    });

    test('weekly streak counts consecutive met weeks; current week in progress does not break it', () {
      final h = _habit(frequency: HabitFrequency.weekly, weeklyTarget: 2, history: {
        // Week of May 27
        '2024-05-27': 1, '2024-05-29': 1,
        // Week of Jun 3
        '2024-06-03': 1, '2024-06-05': 1,
        // Current week (Jun 10) only one so far
        '2024-06-10': 1,
      });
      expect(HabitStats.currentStreak(h, today), 2);

      final metNow = _habit(frequency: HabitFrequency.weekly, weeklyTarget: 2, history: {
        '2024-06-03': 1, '2024-06-05': 1,
        '2024-06-10': 1, '2024-06-11': 1,
      });
      expect(HabitStats.currentStreak(metNow, today), 2);
    });

    test('weekly bestStreak is measured in weeks', () {
      final h = _habit(frequency: HabitFrequency.weekly, weeklyTarget: 1, history: {
        '2024-05-13': 1,
        '2024-05-20': 1,
        '2024-05-27': 1,
        // gap week of Jun 3
        '2024-06-10': 1,
      });
      expect(HabitStats.bestStreak(h), 3);
    });

    test('daily habits are always due', () {
      expect(HabitStats.isDueOn(_habit(), today), isTrue);
    });
  });
}
