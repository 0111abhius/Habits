/// Pure packing of prioritized tasks into a day's work blocks.
///
/// Slots come from the day's timeline plan (30 or 60 minutes each). A slot is
/// available when it is flagged as a work block (or its planned activity is a
/// work activity), is not locked, and is not already holding a different task.
class PlannerSlot {
  final String id;
  final DateTime start;
  final DateTime end;
  final String planactivity;
  final String planNotes;
  final bool workBlock;
  final bool locked;
  final String? taskId;

  const PlannerSlot({
    required this.id,
    required this.start,
    required this.end,
    this.planactivity = '',
    this.planNotes = '',
    this.workBlock = false,
    this.locked = false,
    this.taskId,
  });

  int get minutes => end.difference(start).inMinutes;
}

class PlannerTask {
  final String id;
  final String title;
  final int estimatedMinutes;
  const PlannerTask({required this.id, required this.title, required this.estimatedMinutes});
}

class Placement {
  final PlannerTask task;
  final List<PlannerSlot> slots;
  const Placement(this.task, this.slots);

  DateTime get start => slots.first.start;
  int get minutes => slots.fold(0, (s, x) => s + x.minutes);
}

class PlanResult {
  final List<Placement> placements;
  final List<PlannerTask> unplaced;
  final int freeMinutesBefore;
  final int freeMinutesAfter;
  const PlanResult({
    required this.placements,
    required this.unplaced,
    required this.freeMinutesBefore,
    required this.freeMinutesAfter,
  });

  bool get hasWorkBlocks => freeMinutesBefore > 0 || placements.isNotEmpty;
}

class WorkBlockPlanner {
  WorkBlockPlanner._();

  static const defaultWorkActivities = {'Work', 'Deep Work', 'Deep work', 'Focus'};

  static bool isWorkSlot(PlannerSlot s, {Set<String> workActivities = defaultWorkActivities}) =>
      s.workBlock || workActivities.contains(s.planactivity);

  /// Places [tasks] (already in priority order) into free work slots in time
  /// order. Estimates are rounded up to whole slots. Slots before
  /// [notBefore] (e.g. "now" for today) are skipped. Slots already holding
  /// one of [tasks] are treated as free so re-running is idempotent.
  static PlanResult plan({
    required List<PlannerSlot> slots,
    required List<PlannerTask> tasks,
    DateTime? notBefore,
    Set<String> workActivities = defaultWorkActivities,
  }) {
    final taskIds = tasks.map((t) => t.id).toSet();
    final free = slots.where((s) {
      if (s.locked) return false;
      if (!isWorkSlot(s, workActivities: workActivities)) return false;
      if (notBefore != null && s.start.isBefore(notBefore)) return false;
      final holdsOther = s.taskId != null ? !taskIds.contains(s.taskId) : s.planNotes.trim().isNotEmpty;
      return !holdsOther;
    }).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final freeBefore = free.fold<int>(0, (s, x) => s + x.minutes);
    final placements = <Placement>[];
    final unplaced = <PlannerTask>[];
    var cursor = 0;

    for (final t in tasks) {
      final need = t.estimatedMinutes > 0 ? t.estimatedMinutes : 30;
      var got = 0;
      final taken = <PlannerSlot>[];
      while (got < need && cursor < free.length) {
        taken.add(free[cursor]);
        got += free[cursor].minutes;
        cursor++;
      }
      if (taken.isEmpty) {
        unplaced.add(t);
      } else {
        // A task that ran out of room is still placed (short); the caller can
        // see this from Placement.minutes < estimatedMinutes.
        placements.add(Placement(t, taken));
      }
    }
    final freeAfter = free.skip(cursor).fold<int>(0, (s, x) => s + x.minutes);
    return PlanResult(
      placements: placements,
      unplaced: unplaced,
      freeMinutesBefore: freeBefore,
      freeMinutesAfter: freeAfter,
    );
  }
}
