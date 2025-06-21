import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/utils/categories.dart';

void main() {
  group('Category utilities', () {
    test('displayactivity adds emoji when known', () {
      expect(displayactivity('Study'), '📚 Study');
      expect(displayactivity('Hobby'), '🎨 Hobby');
    });

    test('displayactivity falls back to raw string', () {
      const raw = 'Surfing';
      expect(displayactivity(raw), raw);
    });

    test('kDefaultActivities list includes common categories', () {
      expect(kDefaultActivities, contains('Social'));
      expect(kDefaultActivities.length, greaterThanOrEqualTo(8));
    });
  });
}