import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/models/plan_import.dart';

const _fullPlan = '''
```json
{
  "version": 1,
  "settings": {
    "wakeTime": "7:00",
    "sleepTime": "11:00 PM",
    "goal": "Three anchors hold the day.",
    "topTasksLimit": 3,
    "reminders": { "enabled": true, "planTomorrow": "16:30", "eveningLog": "21:30" }
  },
  "folders": ["Work", "Routines"],
  "habits": [
    { "name": "Meditation", "frequency": "daily", "tier": 1, "reminder": "07:20" },
    { "name": "Workout", "frequency": "3x/week", "tier": 2 },
    { "name": "Water", "type": "counter", "targetCount": 8 }
  ],
  "templates": [
    {
      "name": "Office weekday",
      "days": "weekdays",
      "blocks": [
        { "start": "23:00", "end": "07:00", "activity": "Sleep", "locked": true },
        { "start": "07:40", "end": "08:10", "activity": "Exercise", "days": ["mon", "wed", "fri"] },
        { "start": "08:30", "end": "08:40", "activity": "Planning", "note": "Launch", "locked": true },
        { "start": "08:40", "end": "10:00", "activity": "Deep Work", "workBlock": true },
        { "start": "10:00", "end": "11:00", "activity": "Meeting", "locked": true }
      ]
    },
    { "name": "WFH", "days": [], "blocks": [ { "start": "09:00", "end": "12:00", "activity": "Deep Work", "workBlock": true } ] }
  ],
  "tasks": [
    { "title": "Weekly reset", "folder": "Routines", "estimatedMinutes": 30, "repeat": "weekly:sun" },
    "Buy milk"
  ]
}
```
''';

void main() {
  group('PlanTime', () {
    test('parses common forms', () {
      expect(PlanTime.parse('07:00'), 420);
      expect(PlanTime.parse('7:00'), 420);
      expect(PlanTime.parse('7am'), 420);
      expect(PlanTime.parse('7:30 PM'), 19 * 60 + 30);
      expect(PlanTime.parse('12:00 am'), 0);
      expect(PlanTime.parse('12pm'), 720);
      expect(PlanTime.parse('23:59'), 1439);
      expect(PlanTime.parse('24:00'), 0);
    });

    test('rejects garbage', () {
      expect(PlanTime.parse('7'), isNull);
      expect(PlanTime.parse('25:00'), isNull);
      expect(PlanTime.parse('noon'), isNull);
      expect(PlanTime.parse('13pm'), isNull);
    });

    test('formats', () {
      expect(PlanTime.format(420), '07:00');
      expect(PlanTime.format(1439), '23:59');
    });
  });

  group('PlanDays', () {
    test('parses names, groups and numbers', () {
      expect(PlanDays.parse(['mon', 'Wednesday', 5]), [1, 3, 5]);
      expect(PlanDays.parse('weekdays'), [1, 2, 3, 4, 5]);
      expect(PlanDays.parse('weekend'), [6, 7]);
      expect(PlanDays.parse('mon, wed / fri'), [1, 3, 5]);
      expect(PlanDays.parse(null), isEmpty);
      expect(PlanDays.parse(['funday']), isNull);
      expect(PlanDays.parse([0]), isNull);
    });

    test('labels', () {
      expect(PlanDays.label([1, 2, 3, 4, 5]), 'Weekdays');
      expect(PlanDays.label([1, 3, 5]), 'Mon, Wed, Fri');
      expect(PlanDays.label([1, 2, 3, 4, 5, 6, 7]), 'Every day');
    });
  });

  group('PlanImportParser', () {
    test('parses a full plan including fenced JSON and lenient values', () {
      final r = PlanImportParser.parse(_fullPlan);
      expect(r.errors, isEmpty, reason: r.errors.join('\n'));
      final p = r.plan!;
      expect(p.settings!.wakeMinutes, 420);
      expect(p.settings!.sleepMinutes, 23 * 60);
      expect(p.settings!.planTomorrowReminder, 16 * 60 + 30);
      expect(p.settings!.remindersEnabled, isTrue);
      expect(p.folders, ['Work', 'Routines']);

      expect(p.habits.length, 3);
      expect(p.habits[0].tier, 1);
      expect(p.habits[0].reminderMinutes, 7 * 60 + 20);
      expect(p.habits[1].frequency, 'weekly');
      expect(p.habits[1].weeklyTarget, 3);
      expect(p.habits[2].type, 'counter');
      expect(p.habits[2].targetCount, 8);

      expect(p.templates.length, 2);
      expect(p.templates[0].days, [1, 2, 3, 4, 5]);
      expect(p.templates[0].blocks.length, 5);
      expect(p.templates[0].blocks[1].days, [1, 3, 5]);
      expect(p.templates[1].days, isEmpty);

      expect(p.tasks.length, 2);
      expect(p.tasks[0].repeat, 'weekly:sun');
      expect(p.tasks[1].title, 'Buy milk');

      expect(p.referencedActivities(), containsAll(['Sleep', 'Exercise', 'Planning', 'Deep Work', 'Meeting']));
    });

    test('warns about sub-30-minute blocks instead of failing', () {
      final r = PlanImportParser.parse(_fullPlan);
      expect(r.warnings.any((w) => w.message.contains('08:30–08:40 Planning')), isTrue);
    });

    test('reports errors with paths', () {
      final r = PlanImportParser.parse('''
      { "habits": [ { "name": "", "tier": 9 } ],
        "templates": [ { "name": "A", "days": ["mon"], "blocks": [ { "start": "9:00", "end": "9:00", "activity": "X" }, { "start": "bad", "end": "10:00", "activity": "" } ] },
                       { "name": "B", "days": ["mon"], "blocks": [] } ],
        "tasks": [ { "title": "T", "repeat": "fortnightly" } ] }
      ''');
      expect(r.ok, isFalse);
      final paths = r.errors.map((e) => e.path).toList();
      expect(paths, contains('habits[0].name'));
      expect(paths, contains('templates[0].blocks[0]'));
      expect(paths, contains('templates[0].blocks[1].start'));
      expect(paths, contains('templates[0].blocks[1].activity'));
      expect(paths, contains('tasks[0].repeat'));
      expect(r.errors.any((e) => e.message.contains('claimed by both')), isTrue);
    });

    test('rejects non-JSON and empty plans', () {
      expect(PlanImportParser.parse('hello').ok, isFalse);
      expect(PlanImportParser.parse('[]').ok, isFalse);
      expect(PlanImportParser.parse('{}').ok, isFalse);
      expect(PlanImportParser.parse('').ok, isFalse);
    });

    test('unknown keys are warnings only', () {
      final r = PlanImportParser.parse('{"habits":[{"name":"Read"}],"phoneRules":["no phone"]}');
      expect(r.ok, isTrue);
      expect(r.warnings.single.path, 'phoneRules');
    });
  });

  group('TemplateSlotResolver', () {
    ImportBlock b(String s, String e, String a, {bool locked = false, bool work = false, List<int> days = const []}) =>
        ImportBlock(start: PlanTime.parse(s)!, end: PlanTime.parse(e)!, activity: a, locked: locked, workBlock: work, days: days);

    test('whole hours become single 60-minute slots', () {
      final slots = TemplateSlotResolver.resolve([b('09:00', '11:00', 'Deep Work', work: true)]);
      expect(slots.map((s) => s.id), ['0900', '1000']);
      expect(slots.every((s) => s.durationMinutes == 60 && s.workBlock), isTrue);
    });

    test('half-hour boundaries split the hour', () {
      final slots = TemplateSlotResolver.resolve([
        b('08:30', '09:00', 'Planning', locked: true),
        b('09:00', '10:00', 'Deep Work'),
      ]);
      expect(slots.map((s) => '${s.id}:${s.activity}'), ['0800:', '0830:Planning', '0900:Deep Work']);
      expect(slots[1].locked, isTrue);
      expect(slots[1].durationMinutes, 30);
    });

    test('sleep across midnight fills both ends', () {
      final slots = TemplateSlotResolver.resolve([b('23:00', '07:00', 'Sleep', locked: true)]);
      final ids = slots.map((s) => s.id).toList();
      expect(ids.first, '0000');
      expect(ids, contains('0600'));
      expect(ids, contains('2300'));
      expect(ids, isNot(contains('0700')));
      expect(slots.length, 8);
      expect(slots.first.toEntryMap()['activity'], 'Sleep');
    });

    test('each half-hour goes to the block with the most overlap', () {
      // 07:20-07:40 meditation is 10 min in each half; loses to neighbours.
      final slots = TemplateSlotResolver.resolve([
        b('07:00', '07:20', 'Personal'),
        b('07:20', '07:40', 'Meditation'),
        b('07:40', '08:10', 'Exercise'),
      ]);
      final m = {for (final s in slots) s.id: s.activity};
      expect(m['0700'], 'Personal');
      expect(m['0730'], 'Exercise');
      expect(m['0800'], 'Exercise');
      expect(m.values, isNot(contains('Meditation')));
    });

    test('per-block days expand into one template per signature', () {
      final t = ImportTemplate(name: 'Office', days: [1, 2, 3, 4, 5], blocks: [
        b('09:00', '10:00', 'Work', work: true),
        b('07:30', '08:00', 'Exercise', days: [1, 3, 5]),
      ]);
      final expanded = TemplateSlotResolver.expand(t);
      expect(expanded.length, 2);
      final mwf = expanded.firstWhere((e) => e.days.contains(1));
      final tt = expanded.firstWhere((e) => e.days.contains(2));
      expect(mwf.name, 'Office (Mon, Wed, Fri)');
      expect(mwf.days, [1, 3, 5]);
      expect(tt.name, 'Office (Tue, Thu)');
      expect(mwf.slots.any((s) => s.activity == 'Exercise'), isTrue);
      expect(tt.slots.any((s) => s.activity == 'Exercise'), isFalse);
    });

    test('template without per-block days stays whole', () {
      final t = ImportTemplate(name: 'Sat', days: [6], blocks: [b('10:00', '12:00', 'Admin')]);
      final expanded = TemplateSlotResolver.expand(t);
      expect(expanded.single.name, 'Sat');
      expect(expanded.single.slots.length, 2);
    });
  });
}
