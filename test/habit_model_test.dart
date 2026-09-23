import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/models/habit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  group('Habit model', () {
    test('toMap / fromMap round-trip retains all fields', () {
      final habit = Habit(
        id: 'h1',
        name: 'Drink Water',
        type: HabitType.counter,
        frequency: HabitFrequency.weekly,
        weeklyTarget: 4,
        targetCount: 8,
        userId: 'u1',
        completedDates: [
          DateTime(2024, 01, 01),
          DateTime(2024, 01, 02),
        ],
        createdAt: DateTime(2023, 12, 31),
        archived: true,
        sortOrder: 7,
        reminderTime: '08:30',
        history: const {'2024-01-01': 8, '2024-01-02': 3},
      );

      final reconstructed = Habit.fromMap(habit.id, habit.toMap());

      expect(reconstructed.id, habit.id);
      expect(reconstructed.name, habit.name);
      expect(reconstructed.type, habit.type);
      expect(reconstructed.frequency, habit.frequency);
      expect(reconstructed.weeklyTarget, 4);
      expect(reconstructed.targetCount, 8);
      expect(reconstructed.userId, habit.userId);
      expect(reconstructed.archived, isTrue);
      expect(reconstructed.sortOrder, 7);
      expect(reconstructed.reminderTime, '08:30');
      expect(reconstructed.history, habit.history);

      expect(reconstructed.completedDates.length, habit.completedDates.length);
      for (var i = 0; i < habit.completedDates.length; i++) {
        expect(reconstructed.completedDates[i], habit.completedDates[i]);
      }
      expect(reconstructed.createdAt, habit.createdAt);
    });

    test('fromMap applies defaults for legacy documents', () {
      final habit = Habit.fromMap('h', {
        'name': 'Read',
        'type': 'binary',
        'frequency': 'daily',
        'userId': 'u',
        'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
      });
      expect(habit.weeklyTarget, 3);
      expect(habit.targetCount, 1);
      expect(habit.archived, isFalse);
      expect(habit.sortOrder, 0);
      expect(habit.reminderTime, isNull);
      expect(habit.history, isEmpty);
      expect(habit.frequencyLabel, 'Every day');
    });

    test('legacy threeTimesWeek maps to weekly with target 3', () {
      final habit = Habit.fromMap('h', {
        'name': 'Gym',
        'type': 'binary',
        'frequency': 'threeTimesWeek',
        'userId': 'u',
        'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
      });
      expect(habit.frequency, HabitFrequency.weekly);
      expect(habit.weeklyTarget, 3);
      expect(habit.frequencyLabel, '3x / week');
    });

    test('history tolerates bool and num values', () {
      final habit = Habit.fromMap('h', {
        'name': 'Gym',
        'type': 'binary',
        'frequency': 'daily',
        'userId': 'u',
        'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
        'history': {'2024-01-01': true, '2024-01-02': 2.0, '2024-01-03': 'x'},
      });
      expect(habit.history, {'2024-01-01': 1, '2024-01-02': 2});
    });

    test('copyWith overrides only provided values and can clear reminder', () {
      final original = Habit(
        id: 'h2',
        name: 'Exercise',
        type: HabitType.binary,
        frequency: HabitFrequency.daily,
        userId: 'u99',
        createdAt: DateTime(2024, 01, 10),
        reminderTime: '07:00',
      );

      final modified = original.copyWith(
        name: 'Meditate',
        frequency: HabitFrequency.weekly,
        weeklyTarget: 5,
      );

      expect(modified.name, 'Meditate');
      expect(modified.frequency, HabitFrequency.weekly);
      expect(modified.weeklyTarget, 5);
      expect(modified.reminderTime, '07:00');

      expect(modified.id, original.id);
      expect(modified.type, original.type);
      expect(modified.userId, original.userId);
      expect(modified.createdAt, original.createdAt);

      final cleared = original.copyWith(clearReminder: true);
      expect(cleared.reminderTime, isNull);
    });
  });
}
