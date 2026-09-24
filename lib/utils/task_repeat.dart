/// Recurrence rules for tasks, stored as a compact string on [Task.repeat].
///
/// Supported forms (case-insensitive):
/// - `daily`
/// - `weekdays` (Mon-Fri)
/// - `weekly:sun` / `weekly:mon,wed,fri` — on the given weekdays
/// - `monthly:15` — on that day of the month
class TaskRepeat {
  TaskRepeat._();

  static const _dayNames = {
    'mon': 1, 'monday': 1,
    'tue': 2, 'tues': 2, 'tuesday': 2,
    'wed': 3, 'wednesday': 3,
    'thu': 4, 'thur': 4, 'thurs': 4, 'thursday': 4,
    'fri': 5, 'friday': 5,
    'sat': 6, 'saturday': 6,
    'sun': 7, 'sunday': 7,
  };

  /// Normalizes a rule or returns null when it is not understood.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final r = raw.trim().toLowerCase();
    if (r.isEmpty || r == 'none' || r == 'never') return null;
    if (r == 'daily' || r == 'every day' || r == 'everyday') return 'daily';
    if (r == 'weekdays' || r == 'weekday') return 'weekdays';
    if (r.startsWith('weekly')) {
      final rest = r.contains(':') ? r.substring(r.indexOf(':') + 1) : '';
      final days = rest
          .split(RegExp(r'[,\s/]+'))
          .where((d) => d.isNotEmpty)
          .map((d) => _dayNames[d])
          .whereType<int>()
          .toSet()
          .toList()
        ..sort();
      if (days.isEmpty) return null;
      const short = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
      return 'weekly:${days.map((d) => short[d - 1]).join(',')}';
    }
    if (r.startsWith('monthly')) {
      final rest = r.contains(':') ? r.substring(r.indexOf(':') + 1) : '';
      final day = int.tryParse(rest.trim());
      if (day == null || day < 1 || day > 31) return null;
      return 'monthly:$day';
    }
    // Bare weekday names, e.g. "sun" or "mon,wed".
    final bare = r
        .split(RegExp(r'[,\s/]+'))
        .where((d) => d.isNotEmpty)
        .map((d) => _dayNames[d])
        .toList();
    if (bare.isNotEmpty && bare.every((d) => d != null)) {
      return normalize('weekly:${r.replaceAll(RegExp(r'[\s/]+'), ',')}');
    }
    return null;
  }

  static String label(String? rule) {
    final r = normalize(rule);
    if (r == null) return '';
    if (r == 'daily') return 'Every day';
    if (r == 'weekdays') return 'Weekdays';
    if (r.startsWith('weekly:')) {
      final days = r.substring(7).split(',').map((d) => d[0].toUpperCase() + d.substring(1));
      return 'Every ${days.join(', ')}';
    }
    if (r.startsWith('monthly:')) return 'Monthly on the ${r.substring(8)}';
    return r;
  }

  /// The first date strictly after [after] that matches [rule], or null for
  /// an invalid rule.
  static DateTime? nextOccurrence(String? rule, DateTime after) {
    final r = normalize(rule);
    if (r == null) return null;
    final start = DateTime(after.year, after.month, after.day);
    if (r == 'daily') return start.add(const Duration(days: 1));
    if (r == 'weekdays') {
      var d = start.add(const Duration(days: 1));
      while (d.weekday > 5) {
        d = d.add(const Duration(days: 1));
      }
      return d;
    }
    if (r.startsWith('weekly:')) {
      final days = r.substring(7).split(',').map((d) => _dayNames[d]!).toSet();
      var d = start.add(const Duration(days: 1));
      for (int i = 0; i < 7; i++) {
        if (days.contains(d.weekday)) return d;
        d = d.add(const Duration(days: 1));
      }
      return null;
    }
    if (r.startsWith('monthly:')) {
      final day = int.parse(r.substring(8));
      for (int i = 0; i < 3; i++) {
        final year = start.year + ((start.month + i) > 12 ? 1 : 0);
        final month = ((start.month + i - 1) % 12) + 1;
        final lastDay = DateTime(year, month + 1, 0).day;
        final candidate = DateTime(year, month, day > lastDay ? lastDay : day);
        if (candidate.isAfter(start)) return candidate;
      }
      return null;
    }
    return null;
  }
}
