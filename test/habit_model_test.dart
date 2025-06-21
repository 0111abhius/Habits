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
        frequency: HabitFrequency.daily,
        userId: 'u1',
        completedDates: [
          DateTime(2024, 01, 01),
          DateTime(2024, 01, 02),
        ],
        createdAt: DateTime(2023, 12, 31),
      );

      // Convert to map then back again
      final map = habit.toMap();
      final reconstructed = Habit.fromMap(habit.id, map);

      // Basic scalar fields
      expect(reconstructed.id, habit.id);
      expect(reconstructed.name, habit.name);
      expect(reconstructed.type, habit.type);
      expect(reconstructed.frequency, habit.frequency);
      expect(reconstructed.userId, habit.userId);

      // List & DateTime fields
      expect(reconstructed.completedDates.length, habit.completedDates.length);
      for (var i = 0; i < habit.completedDates.length; i++) {
        expect(reconstructed.completedDates[i], habit.completedDates[i]);
      }
      expect(reconstructed.createdAt, habit.createdAt);
    });

    test('copyWith overrides only provided values', () {
      final original = Habit(
        id: 'h2',
        name: 'Exercise',
        type: HabitType.binary,
        frequency: HabitFrequency.daily,
        userId: 'u99',
        completedDates: const [],
        createdAt: DateTime(2024, 01, 10),
      );

      final modified = original.copyWith(
        name: 'Meditate',
        frequency: HabitFrequency.threeTimesWeek,
      );

      // Changed fields
      expect(modified.name, 'Meditate');
      expect(modified.frequency, HabitFrequency.threeTimesWeek);

      // Unchanged fields
      expect(modified.id, original.id);
      expect(modified.type, original.type);
      expect(modified.userId, original.userId);
      expect(modified.completedDates, original.completedDates);
      expect(modified.createdAt, original.createdAt);
    });
  });
}