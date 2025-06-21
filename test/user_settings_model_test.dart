import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/models/user_settings.dart';

void main() {
  group('UserSettings model', () {
    final settings = UserSettings(
      userId: 'user1',
      sleepTime: const TimeOfDay(hour: 22, minute: 30),
      wakeTime: const TimeOfDay(hour: 6, minute: 0),
      customActivities: const ['Yoga', 'Reading'],
    );

    test('toMap / fromMap round-trip', () {
      final map = settings.toMap();
      final reconstructed = UserSettings.fromMap(map);

      expect(reconstructed.userId, settings.userId);
      expect(reconstructed.sleepTime, settings.sleepTime);
      expect(reconstructed.wakeTime, settings.wakeTime);
      expect(reconstructed.customActivities, settings.customActivities);
    });

    test('copyWith overrides selected fields', () {
      final modified = settings.copyWith(
        sleepTime: const TimeOfDay(hour: 23, minute: 0),
      );

      expect(modified.sleepTime, const TimeOfDay(hour: 23, minute: 0));
      // unchanged
      expect(modified.wakeTime, settings.wakeTime);
      expect(modified.customActivities, settings.customActivities);
      expect(modified.userId, settings.userId);
    });
  });
}