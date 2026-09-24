import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/utils/activities.dart';

void main() {
  group('Activity utilities', () {
    test('displayActivity returns emoji + label when known', () {
      expect(displayActivity('Sleep'), '😴 Sleep');
      expect(displayActivity('Work'), '💼 Work');
    });

    test('displayActivity returns original label for unknown', () {
      const unknown = 'Skydiving';
      expect(displayActivity(unknown), unknown);
    });

    test('kDefaultActivities list contains base categories', () {
      expect(kDefaultActivities, containsAll(['Sleep', 'Work', 'Other']));
    });
  });
}