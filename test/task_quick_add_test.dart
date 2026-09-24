import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/utils/task_quick_add.dart';

void main() {
  // Wednesday 2024-06-12.
  final now = DateTime(2024, 6, 12, 10);
  const folders = ['Work', 'Home', 'Deep Work', 'Someday'];

  QuickAddResult parse(String s) => TaskQuickAdd.parse(s, knownFolders: folders, now: now);

  group('TaskQuickAdd.parse', () {
    test('plain text is just the title', () {
      final r = parse('Buy milk');
      expect(r.title, 'Buy milk');
      expect(r.folder, isNull);
      expect(r.estimatedMinutes, isNull);
      expect(r.isToday, isFalse);
      expect(r.scheduledDate, isNull);
    });

    test('folder hashtag is matched case-insensitively and by prefix', () {
      expect(parse('Write report #work').folder, 'Work');
      expect(parse('Write report #WORK').folder, 'Work');
      expect(parse('Write report #som').folder, 'Someday');
      expect(parse('Write report #work').title, 'Write report');
    });

    test('quoted folder names with spaces', () {
      final r = parse('Refactor parser #"deep work" 1h');
      expect(r.folder, 'Deep Work');
      expect(r.estimatedMinutes, 60);
      expect(r.title, 'Refactor parser');
    });

    test('unknown hashtag stays in the title', () {
      final r = parse('Ship #v2 today');
      expect(r.folder, isNull);
      expect(r.title, 'Ship #v2');
      expect(r.isToday, isTrue);
    });

    test('duration tokens', () {
      expect(parse('Call mom 30m').estimatedMinutes, 30);
      expect(parse('Call mom 45min').estimatedMinutes, 45);
      expect(parse('Call mom 1h').estimatedMinutes, 60);
      expect(parse('Call mom 1.5h').estimatedMinutes, 90);
      expect(parse('Call mom 2hr').estimatedMinutes, 120);
      expect(parse('Call mom 30m').title, 'Call mom');
    });

    test('today variants', () {
      expect(parse('Pay rent today').isToday, isTrue);
      expect(parse('Pay rent !today').isToday, isTrue);
      expect(parse('Pay rent tod').isToday, isTrue);
      expect(parse('Pay rent @today').isToday, isTrue);
      expect(parse('Pay rent today').title, 'Pay rent');
    });

    test('tomorrow schedules for the next day', () {
      for (final t in ['tomorrow', 'tmr', 'tmrw', '@tomorrow']) {
        final r = parse('Dentist $t');
        expect(r.scheduledDate, DateTime(2024, 6, 13), reason: t);
        expect(r.title, 'Dentist');
      }
    });

    test('explicit weekday schedules the next occurrence', () {
      expect(parse('Gym @fri').scheduledDate, DateTime(2024, 6, 14));
      // Same weekday as today rolls to next week.
      expect(parse('Gym @wed').scheduledDate, DateTime(2024, 6, 19));
      // Earlier in the week wraps to next week.
      expect(parse('Gym @mon').scheduledDate, DateTime(2024, 6, 17));
    });

    test('full weekday names work without @, short ones do not', () {
      expect(parse('Plan friday').scheduledDate, DateTime(2024, 6, 14));
      expect(parse('Plan friday').title, 'Plan');
      final r = parse('Watch the sun set');
      expect(r.scheduledDate, isNull);
      expect(r.title, 'Watch the sun set');
    });

    test('everything combined', () {
      final r = parse('Write quarterly review #work 1.5h @fri');
      expect(r.title, 'Write quarterly review');
      expect(r.folder, 'Work');
      expect(r.estimatedMinutes, 90);
      expect(r.scheduledDate, DateTime(2024, 6, 14));
    });

    test('input consisting only of tokens keeps the raw text as title', () {
      final r = parse('30m');
      expect(r.estimatedMinutes, 30);
      expect(r.title, '30m');
    });
  });
}
