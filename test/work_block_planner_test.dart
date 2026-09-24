import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/utils/task_repeat.dart';
import 'package:habit_logger/utils/work_block_planner.dart';

PlannerSlot _slot(int h, int m, int dur, String act, {bool work = false, bool locked = false, String notes = '', String? taskId}) {
  final start = DateTime(2024, 6, 12, h, m);
  return PlannerSlot(
    id: '$h$m',
    start: start,
    end: start.add(Duration(minutes: dur)),
    planactivity: act,
    planNotes: notes,
    workBlock: work,
    locked: locked,
    taskId: taskId,
  );
}

void main() {
  group('WorkBlockPlanner', () {
    final slots = [
      _slot(8, 30, 30, 'Planning', locked: true),
      _slot(9, 0, 60, 'Deep Work', work: true),
      _slot(10, 0, 60, 'Meeting', locked: true),
      _slot(11, 30, 30, 'Work', work: true),
      _slot(12, 0, 60, 'Meal'),
      _slot(13, 0, 60, 'Work', work: true),
      _slot(14, 0, 60, 'Work', work: true, notes: 'Existing thing', taskId: 'other'),
      _slot(15, 0, 60, 'Work'), // work activity without flag counts too
    ];

    test('fills tasks in priority order into time-ordered free work slots', () {
      final r = WorkBlockPlanner.plan(slots: slots, tasks: const [
        PlannerTask(id: 'a', title: 'A', estimatedMinutes: 60),
        PlannerTask(id: 'b', title: 'B', estimatedMinutes: 45),
        PlannerTask(id: 'c', title: 'C', estimatedMinutes: 30),
      ]);
      expect(r.freeMinutesBefore, 60 + 30 + 60 + 60);
      expect(r.placements.length, 3);
      expect(r.placements[0].slots.map((s) => s.id), ['90']);
      // 45 min rounds up: 30-min slot + next 60-min slot.
      expect(r.placements[1].slots.map((s) => s.id), ['1130', '130']);
      expect(r.placements[2].slots.map((s) => s.id), ['150']);
      expect(r.unplaced, isEmpty);
      expect(r.freeMinutesAfter, 0);
    });

    test('locked, non-work and occupied slots are never used', () {
      final r = WorkBlockPlanner.plan(slots: slots, tasks: const [
        PlannerTask(id: 'x', title: 'X', estimatedMinutes: 600),
      ]);
      final used = r.placements.single.slots.map((s) => s.id).toSet();
      expect(used, isNot(contains('830')));
      expect(used, isNot(contains('100')));
      expect(used, isNot(contains('120')));
      expect(used, isNot(contains('140')));
    });

    test('unplaced when there is no room', () {
      final r = WorkBlockPlanner.plan(slots: slots, tasks: const [
        PlannerTask(id: 'x', title: 'X', estimatedMinutes: 240),
        PlannerTask(id: 'y', title: 'Y', estimatedMinutes: 30),
      ]);
      expect(r.placements.single.task.id, 'x');
      expect(r.placements.single.minutes, 210); // short
      expect(r.unplaced.map((t) => t.id), ['y']);
    });

    test('re-running treats slots holding the same tasks as free', () {
      final withOwn = [...slots, _slot(16, 0, 60, 'Work', work: true, notes: 'A', taskId: 'a')];
      final r = WorkBlockPlanner.plan(slots: withOwn, tasks: const [
        PlannerTask(id: 'a', title: 'A', estimatedMinutes: 60),
      ]);
      expect(r.freeMinutesBefore, 60 + 30 + 60 + 60 + 60);
    });

    test('notBefore skips slots already in the past', () {
      final r = WorkBlockPlanner.plan(
        slots: slots,
        notBefore: DateTime(2024, 6, 12, 12, 30),
        tasks: const [PlannerTask(id: 'a', title: 'A', estimatedMinutes: 30)],
      );
      expect(r.placements.single.slots.single.id, '130');
    });

    test('no work blocks at all', () {
      final r = WorkBlockPlanner.plan(
        slots: [_slot(9, 0, 60, 'Meal')],
        tasks: const [PlannerTask(id: 'a', title: 'A', estimatedMinutes: 30)],
      );
      expect(r.hasWorkBlocks, isFalse);
      expect(r.unplaced.length, 1);
    });
  });

  group('TaskRepeat', () {
    test('normalizes rules', () {
      expect(TaskRepeat.normalize('Daily'), 'daily');
      expect(TaskRepeat.normalize('weekdays'), 'weekdays');
      expect(TaskRepeat.normalize('weekly:Sun'), 'weekly:sun');
      expect(TaskRepeat.normalize('weekly: fri, mon'), 'weekly:mon,fri');
      expect(TaskRepeat.normalize('sun'), 'weekly:sun');
      expect(TaskRepeat.normalize('monthly:15'), 'monthly:15');
      expect(TaskRepeat.normalize('fortnightly'), isNull);
      expect(TaskRepeat.normalize(''), isNull);
      expect(TaskRepeat.normalize('none'), isNull);
    });

    test('next occurrences', () {
      final wed = DateTime(2024, 6, 12); // Wednesday
      expect(TaskRepeat.nextOccurrence('daily', wed), DateTime(2024, 6, 13));
      expect(TaskRepeat.nextOccurrence('weekdays', DateTime(2024, 6, 14)), DateTime(2024, 6, 17));
      expect(TaskRepeat.nextOccurrence('weekly:sun', wed), DateTime(2024, 6, 16));
      expect(TaskRepeat.nextOccurrence('weekly:wed', wed), DateTime(2024, 6, 19));
      expect(TaskRepeat.nextOccurrence('weekly:mon,fri', wed), DateTime(2024, 6, 14));
      expect(TaskRepeat.nextOccurrence('monthly:15', wed), DateTime(2024, 6, 15));
      expect(TaskRepeat.nextOccurrence('monthly:10', wed), DateTime(2024, 7, 10));
      expect(TaskRepeat.nextOccurrence('monthly:31', DateTime(2024, 1, 31)), DateTime(2024, 2, 29));
      expect(TaskRepeat.nextOccurrence('bogus', wed), isNull);
    });

    test('labels', () {
      expect(TaskRepeat.label('weekly:sun'), 'Every Sun');
      expect(TaskRepeat.label('weekdays'), 'Weekdays');
      expect(TaskRepeat.label(null), '');
    });
  });
}
