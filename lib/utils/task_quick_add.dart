/// Parses shorthand typed into the task quick-add box.
///
/// Supported tokens (anywhere in the text, case-insensitive):
/// - `#Folder` or `#"Two words"` – assign to an existing folder
/// - `30m`, `45min`, `1h`, `1.5h`, `2hr` – time estimate
/// - `today`, `!today`, `tod` – flag for today
/// - `tomorrow`, `tmr`, `tmrw` – schedule for tomorrow
/// - `mon`..`sun` / `monday`.. – schedule for the next such weekday
/// - `@today`, `@tomorrow`, `@fri` – explicit schedule prefix form
///
/// Everything else becomes the title.
class QuickAddResult {
  final String title;
  final String? folder;
  final int? estimatedMinutes;
  final bool isToday;
  final DateTime? scheduledDate;

  const QuickAddResult({
    required this.title,
    this.folder,
    this.estimatedMinutes,
    this.isToday = false,
    this.scheduledDate,
  });
}

class TaskQuickAdd {
  TaskQuickAdd._();

  static final _durationRe = RegExp(r'^(\d+(?:\.\d+)?)(m|min|mins|h|hr|hrs)$', caseSensitive: false);
  static const _weekdays = {
    'mon': 1, 'monday': 1,
    'tue': 2, 'tues': 2, 'tuesday': 2,
    'wed': 3, 'wednesday': 3,
    'thu': 4, 'thur': 4, 'thurs': 4, 'thursday': 4,
    'fri': 5, 'friday': 5,
    'sat': 6, 'saturday': 6,
    'sun': 7, 'sunday': 7,
  };

  static QuickAddResult parse(
    String input, {
    required List<String> knownFolders,
    DateTime? now,
  }) {
    final today = _dayOnly(now ?? DateTime.now());
    String? folder;
    int? minutes;
    bool isToday = false;
    DateTime? scheduled;

    String text = input.trim();

    // Quoted folder names: #"Deep work"
    final quoted = RegExp(r'#"([^"]+)"');
    text = text.replaceAllMapped(quoted, (m) {
      final match = _matchFolder(m.group(1)!, knownFolders);
      if (match != null) {
        folder = match;
        return ' ';
      }
      return m.group(0)!;
    });

    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final kept = <String>[];

    for (final raw in words) {
      final w = raw.trim();
      final lower = w.toLowerCase();

      if (w.startsWith('#') && w.length > 1) {
        final match = _matchFolder(w.substring(1), knownFolders);
        if (match != null) {
          folder = match;
          continue;
        }
      }

      final dur = _durationRe.firstMatch(lower);
      if (dur != null) {
        final n = double.parse(dur.group(1)!);
        final unit = dur.group(2)!;
        minutes = unit.startsWith('h') ? (n * 60).round() : n.round();
        continue;
      }

      final bare = lower.startsWith('@') || lower.startsWith('!') ? lower.substring(1) : lower;
      final explicit = bare != lower;
      if (bare == 'today' || bare == 'tod') {
        isToday = true;
        continue;
      }
      if (bare == 'tomorrow' || bare == 'tmr' || bare == 'tmrw') {
        scheduled = today.add(const Duration(days: 1));
        continue;
      }
      // Weekday names only count when explicit (@fri) or 3+ letter full words
      // that are unlikely to be part of a title ("sun" alone is ambiguous, so
      // require the explicit form for 3-letter abbreviations).
      final wd = _weekdays[bare];
      if (wd != null && (explicit || bare.length > 4)) {
        int delta = (wd - today.weekday) % 7;
        if (delta == 0) delta = 7;
        scheduled = today.add(Duration(days: delta));
        continue;
      }

      kept.add(w);
    }

    var title = kept.join(' ').trim();
    if (title.isEmpty) title = input.trim();

    return QuickAddResult(
      title: title,
      folder: folder,
      estimatedMinutes: minutes,
      isToday: isToday,
      scheduledDate: scheduled,
    );
  }

  static String? _matchFolder(String name, List<String> known) {
    final n = name.toLowerCase();
    for (final f in known) {
      if (f.toLowerCase() == n) return f;
    }
    for (final f in known) {
      if (f.toLowerCase().startsWith(n)) return f;
    }
    return null;
  }

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
