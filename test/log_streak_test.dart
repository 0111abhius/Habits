import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/utils/log_streak.dart';

void main() {
  final today = DateTime(2024, 6, 12, 18);

  group('computeLogStreak', () {
    test('zero when nothing is logged', () {
      expect(computeLogStreak(<String>{}, today), 0);
    });

    test('counts consecutive logged days ending today', () {
      expect(computeLogStreak({'2024-06-10', '2024-06-11', '2024-06-12'}, today), 3);
    });

    test('today unfinished does not break the streak', () {
      expect(computeLogStreak({'2024-06-09', '2024-06-10', '2024-06-11'}, today), 3);
    });

    test('gap resets the streak', () {
      expect(computeLogStreak({'2024-06-08', '2024-06-10', '2024-06-11', '2024-06-12'}, today), 3);
    });

    test('a streak that ended two days ago is zero', () {
      expect(computeLogStreak({'2024-06-09', '2024-06-10'}, today), 0);
    });

    test('crosses month boundaries', () {
      expect(computeLogStreak({'2024-05-31', '2024-06-01', '2024-06-02'}, DateTime(2024, 6, 2)), 3);
    });
  });
}
