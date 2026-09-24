import 'dart:convert';

import '../utils/task_repeat.dart';

/// Day Coach plan import format, version 1.
///
/// The file is produced by an LLM (or by hand) from a free-form plan and then
/// pasted into the app, where it is validated, previewed and applied. Nothing
/// in here touches Firestore: this is a pure model + parser so it can be unit
/// tested and so the LLM only ever produces data.
class PlanImport {
  final int version;
  final ImportSettings? settings;
  final List<String> activities;
  final List<String> folders;
  final Map<String, String> folderActivities;
  final List<ImportHabit> habits;
  final List<ImportTemplate> templates;
  final List<ImportTask> tasks;

  const PlanImport({
    this.version = 1,
    this.settings,
    this.activities = const [],
    this.folders = const [],
    this.folderActivities = const {},
    this.habits = const [],
    this.templates = const [],
    this.tasks = const [],
  });

  bool get isEmpty =>
      settings == null &&
      activities.isEmpty &&
      folders.isEmpty &&
      habits.isEmpty &&
      templates.isEmpty &&
      tasks.isEmpty;

  /// Every activity name referenced anywhere in the plan.
  Set<String> referencedActivities() {
    final out = <String>{...activities, ...folderActivities.values};
    for (final t in templates) {
      for (final b in t.blocks) {
        if (b.activity.isNotEmpty) out.add(b.activity);
      }
    }
    for (final t in tasks) {
      if (t.activity != null && t.activity!.isNotEmpty) out.add(t.activity!);
    }
    out.remove('');
    return out;
  }
}

class ImportSettings {
  final int? wakeMinutes;
  final int? sleepMinutes;
  final String? goal;
  final int? topTasksLimit;
  final int? planTomorrowReminder;
  final int? morningPlanReminder;
  final int? eveningLogReminder;
  final bool? remindersEnabled;

  const ImportSettings({
    this.wakeMinutes,
    this.sleepMinutes,
    this.goal,
    this.topTasksLimit,
    this.planTomorrowReminder,
    this.morningPlanReminder,
    this.eveningLogReminder,
    this.remindersEnabled,
  });

  bool get isEmpty =>
      wakeMinutes == null &&
      sleepMinutes == null &&
      goal == null &&
      topTasksLimit == null &&
      planTomorrowReminder == null &&
      morningPlanReminder == null &&
      eveningLogReminder == null &&
      remindersEnabled == null;
}

class ImportHabit {
  final String name;
  final String type; // binary | counter
  final String frequency; // daily | weekly
  final int weeklyTarget;
  final int targetCount;
  final int tier;
  final int? reminderMinutes;

  const ImportHabit({
    required this.name,
    this.type = 'binary',
    this.frequency = 'daily',
    this.weeklyTarget = 3,
    this.targetCount = 1,
    this.tier = 0,
    this.reminderMinutes,
  });
}

class ImportBlock {
  /// Minutes from midnight. [end] may be <= [start] for blocks crossing
  /// midnight (e.g. Sleep 23:00 -> 07:00).
  final int start;
  final int end;
  final String activity;
  final String note;
  final bool locked;
  final bool workBlock;

  /// Weekdays (1=Mon..7=Sun) this block applies to; empty = all days of the
  /// template.
  final List<int> days;

  const ImportBlock({
    required this.start,
    required this.end,
    required this.activity,
    this.note = '',
    this.locked = false,
    this.workBlock = false,
    this.days = const [],
  });

  int get durationMinutes => end > start ? end - start : (1440 - start) + end;

  bool appliesOn(int? weekday) => weekday == null || days.isEmpty || days.contains(weekday);

  String get label => '${PlanTime.format(start)}–${PlanTime.format(end)} $activity';
}

class ImportTemplate {
  final String name;
  final List<int> days;
  final List<ImportBlock> blocks;

  const ImportTemplate({required this.name, this.days = const [], this.blocks = const []});
}

class ImportTask {
  final String title;
  final String? folder;
  final int? estimatedMinutes;
  final String notes;
  final String? repeat;
  final bool today;
  final DateTime? scheduledDate;
  final String? activity;

  const ImportTask({
    required this.title,
    this.folder,
    this.estimatedMinutes,
    this.notes = '',
    this.repeat,
    this.today = false,
    this.scheduledDate,
    this.activity,
  });
}

class ImportIssue {
  final String path;
  final String message;
  final bool isError;
  const ImportIssue(this.path, this.message, {this.isError = true});

  @override
  String toString() => '${isError ? 'error' : 'warning'} at $path: $message';
}

class PlanImportResult {
  final PlanImport? plan;
  final List<ImportIssue> issues;
  const PlanImportResult(this.plan, this.issues);

  List<ImportIssue> get errors => issues.where((i) => i.isError).toList();
  List<ImportIssue> get warnings => issues.where((i) => !i.isError).toList();
  bool get ok => plan != null && errors.isEmpty;
}

/// Time-of-day helpers on "minutes since midnight".
class PlanTime {
  PlanTime._();

  static final _re = RegExp(r'^\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\s*$', caseSensitive: false);

  /// Parses `07:00`, `7:00`, `7am`, `7:30 PM`, `19:00`. Returns null if
  /// invalid.
  static int? parse(dynamic raw) {
    if (raw is int) return (raw >= 0 && raw < 1440) ? raw : null;
    if (raw is! String) return null;
    final m = _re.firstMatch(raw);
    if (m == null) return null;
    var h = int.parse(m.group(1)!);
    final min = int.tryParse(m.group(2) ?? '0') ?? 0;
    final ampm = m.group(3)?.toLowerCase().replaceAll('.', '');
    if (ampm != null) {
      if (h < 1 || h > 12) return null;
      if (ampm == 'pm' && h != 12) h += 12;
      if (ampm == 'am' && h == 12) h = 0;
    } else if (m.group(2) == null) {
      // A bare number without am/pm or minutes is too ambiguous.
      return null;
    }
    if (h == 24 && min == 0) return 0;
    if (h < 0 || h > 23 || min < 0 || min > 59) return null;
    return h * 60 + min;
  }

  static String format(int minutes) {
    final m = minutes % 1440;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }
}

/// Weekday parsing: names, numbers (1=Mon..7=Sun) and the groups
/// `weekdays`, `weekend`, `all`/`daily`.
class PlanDays {
  PlanDays._();

  static const _names = {
    'mon': 1, 'monday': 1,
    'tue': 2, 'tues': 2, 'tuesday': 2,
    'wed': 3, 'wednesday': 3,
    'thu': 4, 'thur': 4, 'thurs': 4, 'thursday': 4,
    'fri': 5, 'friday': 5,
    'sat': 6, 'saturday': 6,
    'sun': 7, 'sunday': 7,
  };

  static const shortNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Returns null when any element cannot be understood.
  static List<int>? parse(dynamic raw) {
    if (raw == null) return const [];
    Iterable items;
    if (raw is String) {
      items = raw.split(RegExp(r'[,\s/]+')).where((s) => s.isNotEmpty);
    } else if (raw is List) {
      items = raw;
    } else {
      return null;
    }
    final out = <int>{};
    for (final item in items) {
      if (item is int) {
        if (item < 1 || item > 7) return null;
        out.add(item);
        continue;
      }
      final s = item.toString().trim().toLowerCase();
      if (s == 'weekdays' || s == 'weekday') {
        out.addAll([1, 2, 3, 4, 5]);
      } else if (s == 'weekend' || s == 'weekends') {
        out.addAll([6, 7]);
      } else if (s == 'all' || s == 'daily' || s == 'every day' || s == '*') {
        out.addAll([1, 2, 3, 4, 5, 6, 7]);
      } else if (_names.containsKey(s)) {
        out.add(_names[s]!);
      } else {
        final n = int.tryParse(s);
        if (n == null || n < 1 || n > 7) return null;
        out.add(n);
      }
    }
    final list = out.toList()..sort();
    return list;
  }

  static String label(List<int> days) {
    if (days.length == 7) return 'Every day';
    if (days.toSet().containsAll([1, 2, 3, 4, 5]) && days.length == 5) return 'Weekdays';
    if (days.toSet().containsAll([6, 7]) && days.length == 2) return 'Weekend';
    return days.map((d) => shortNames[d - 1]).join(', ');
  }
}

/// Parses and validates the JSON import text.
class PlanImportParser {
  PlanImportParser._();

  static const supportedVersion = 1;

  static PlanImportResult parse(String text) {
    final issues = <ImportIssue>[];
    var cleaned = text.trim();
    // Tolerate a fenced code block straight from a chat window.
    final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$', multiLine: false);
    final fm = fence.firstMatch(cleaned);
    if (fm != null) cleaned = fm.group(1)!.trim();
    if (cleaned.isEmpty) {
      return PlanImportResult(null, [const ImportIssue('\$', 'Nothing to import: paste the JSON produced by your LLM.')]);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (e) {
      return PlanImportResult(null, [ImportIssue('\$', 'Not valid JSON: ${_shortError(e)}')]);
    }
    if (decoded is! Map) {
      return PlanImportResult(null, [const ImportIssue('\$', 'The top level must be a JSON object.')]);
    }
    final root = Map<String, dynamic>.from(decoded);

    final version = root['version'];
    if (version != null && version is! int) {
      issues.add(const ImportIssue('version', 'must be an integer'));
    } else if (version is int && version > supportedVersion) {
      issues.add(ImportIssue('version', 'version $version is newer than this app understands ($supportedVersion)'));
    }

    const known = {
      'version', 'settings', 'activities', 'folders', 'folderActivities', 'habits', 'templates', 'tasks', 'notes', '\$schema'
    };
    for (final k in root.keys) {
      if (!known.contains(k)) issues.add(ImportIssue(k, 'unknown top-level key (ignored)', isError: false));
    }

    final settings = _parseSettings(root['settings'], issues);
    final activities = _stringList(root['activities'], 'activities', issues);
    final folders = _stringList(root['folders'], 'folders', issues);
    final folderActivities = <String, String>{};
    final rawFa = root['folderActivities'];
    if (rawFa is Map) {
      rawFa.forEach((k, v) {
        if (v is String && v.trim().isNotEmpty) folderActivities[k.toString()] = v.trim();
      });
    } else if (rawFa != null) {
      issues.add(const ImportIssue('folderActivities', 'must be an object of folder -> activity'));
    }

    final habits = <ImportHabit>[];
    final rawHabits = root['habits'];
    if (rawHabits is List) {
      for (var i = 0; i < rawHabits.length; i++) {
        final h = _parseHabit(rawHabits[i], 'habits[$i]', issues);
        if (h != null) habits.add(h);
      }
    } else if (rawHabits != null) {
      issues.add(const ImportIssue('habits', 'must be a list'));
    }
    _checkDuplicates(habits.map((h) => h.name), 'habits', issues);

    final templates = <ImportTemplate>[];
    final rawTemplates = root['templates'];
    if (rawTemplates is List) {
      for (var i = 0; i < rawTemplates.length; i++) {
        final t = _parseTemplate(rawTemplates[i], 'templates[$i]', issues);
        if (t != null) templates.add(t);
      }
    } else if (rawTemplates != null) {
      issues.add(const ImportIssue('templates', 'must be a list'));
    }
    _checkDuplicates(templates.map((t) => t.name), 'templates', issues);
    _checkTemplateDayOverlap(templates, issues);

    final tasks = <ImportTask>[];
    final rawTasks = root['tasks'];
    if (rawTasks is List) {
      for (var i = 0; i < rawTasks.length; i++) {
        final t = _parseTask(rawTasks[i], 'tasks[$i]', issues, folders);
        if (t != null) tasks.add(t);
      }
    } else if (rawTasks != null) {
      issues.add(const ImportIssue('tasks', 'must be a list'));
    }

    final plan = PlanImport(
      version: version is int ? version : 1,
      settings: settings == null || settings.isEmpty ? null : settings,
      activities: activities,
      folders: folders,
      folderActivities: folderActivities,
      habits: habits,
      templates: templates,
      tasks: tasks,
    );
    if (plan.isEmpty && issues.where((i) => i.isError).isEmpty) {
      issues.add(const ImportIssue('\$', 'The plan has no settings, habits, templates or tasks.'));
    }
    final hasErrors = issues.any((i) => i.isError);
    return PlanImportResult(hasErrors ? null : plan, issues);
  }

  static String _shortError(Object e) {
    final s = e.toString();
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  static List<String> _stringList(dynamic raw, String path, List<ImportIssue> issues) {
    if (raw == null) return const [];
    if (raw is! List) {
      issues.add(ImportIssue(path, 'must be a list of strings'));
      return const [];
    }
    final out = <String>[];
    for (var i = 0; i < raw.length; i++) {
      final v = raw[i];
      if (v is String && v.trim().isNotEmpty) {
        if (!out.contains(v.trim())) out.add(v.trim());
      } else {
        issues.add(ImportIssue('$path[$i]', 'must be a non-empty string'));
      }
    }
    return out;
  }

  static int? _time(dynamic raw, String path, List<ImportIssue> issues, {bool required = false}) {
    if (raw == null) {
      if (required) issues.add(ImportIssue(path, 'is required (HH:mm)'));
      return null;
    }
    final t = PlanTime.parse(raw);
    if (t == null) issues.add(ImportIssue(path, '"$raw" is not a time; use 24h HH:mm like "07:30"'));
    return t;
  }

  static ImportSettings? _parseSettings(dynamic raw, List<ImportIssue> issues) {
    if (raw == null) return null;
    if (raw is! Map) {
      issues.add(const ImportIssue('settings', 'must be an object'));
      return null;
    }
    final m = Map<String, dynamic>.from(raw);
    final reminders = m['reminders'] is Map ? Map<String, dynamic>.from(m['reminders']) : const <String, dynamic>{};
    int? limit;
    if (m['topTasksLimit'] != null) {
      if (m['topTasksLimit'] is int && m['topTasksLimit'] >= 1 && m['topTasksLimit'] <= 10) {
        limit = m['topTasksLimit'];
      } else {
        issues.add(const ImportIssue('settings.topTasksLimit', 'must be an integer 1-10'));
      }
    }
    return ImportSettings(
      wakeMinutes: _time(m['wakeTime'], 'settings.wakeTime', issues),
      sleepMinutes: _time(m['sleepTime'], 'settings.sleepTime', issues),
      goal: (m['goal'] is String && (m['goal'] as String).trim().isNotEmpty) ? (m['goal'] as String).trim() : null,
      topTasksLimit: limit,
      planTomorrowReminder: _time(reminders['planTomorrow'], 'settings.reminders.planTomorrow', issues),
      morningPlanReminder: _time(reminders['morningPlan'], 'settings.reminders.morningPlan', issues),
      eveningLogReminder: _time(reminders['eveningLog'], 'settings.reminders.eveningLog', issues),
      remindersEnabled: reminders['enabled'] is bool ? reminders['enabled'] as bool : null,
    );
  }

  static ImportHabit? _parseHabit(dynamic raw, String path, List<ImportIssue> issues) {
    if (raw is! Map) {
      issues.add(ImportIssue(path, 'must be an object'));
      return null;
    }
    final m = Map<String, dynamic>.from(raw);
    final name = (m['name'] ?? '').toString().trim();
    if (name.isEmpty) {
      issues.add(ImportIssue('$path.name', 'is required'));
      return null;
    }
    var type = (m['type'] ?? 'binary').toString().toLowerCase().trim();
    if (type == 'checkbox' || type == 'boolean' || type == 'yesno') type = 'binary';
    if (type == 'count' || type == 'number') type = 'counter';
    if (type != 'binary' && type != 'counter') {
      issues.add(ImportIssue('$path.type', '"$type" must be "binary" or "counter"'));
      type = 'binary';
    }
    var frequency = (m['frequency'] ?? 'daily').toString().toLowerCase().trim();
    int weeklyTarget = 3;
    final wt = m['weeklyTarget'] ?? m['timesPerWeek'];
    if (wt != null) {
      if (wt is int && wt >= 1 && wt <= 7) {
        weeklyTarget = wt;
      } else {
        issues.add(ImportIssue('$path.weeklyTarget', 'must be an integer 1-7'));
      }
    }
    final freqMatch = RegExp(r'^(\d)\s*x?\s*(?:/|per)?\s*week').firstMatch(frequency);
    if (freqMatch != null) {
      frequency = 'weekly';
      weeklyTarget = int.parse(freqMatch.group(1)!).clamp(1, 7);
    }
    if (frequency == 'every day' || frequency == 'everyday') frequency = 'daily';
    if (frequency != 'daily' && frequency != 'weekly') {
      issues.add(ImportIssue('$path.frequency', '"$frequency" must be "daily" or "weekly" (with weeklyTarget)'));
      frequency = 'daily';
    }
    int targetCount = 1;
    final tc = m['targetCount'] ?? m['target'];
    if (tc != null) {
      if (tc is int && tc >= 1) {
        targetCount = tc;
      } else {
        issues.add(ImportIssue('$path.targetCount', 'must be a positive integer'));
      }
    }
    int tier = 0;
    if (m['tier'] != null) {
      if (m['tier'] is int && m['tier'] >= 1 && m['tier'] <= 3) {
        tier = m['tier'];
      } else {
        issues.add(ImportIssue('$path.tier', 'must be 1, 2 or 3'));
      }
    }
    return ImportHabit(
      name: name,
      type: type,
      frequency: frequency,
      weeklyTarget: weeklyTarget,
      targetCount: targetCount,
      tier: tier,
      reminderMinutes: _time(m['reminder'] ?? m['reminderTime'], '$path.reminder', issues),
    );
  }

  static ImportTemplate? _parseTemplate(dynamic raw, String path, List<ImportIssue> issues) {
    if (raw is! Map) {
      issues.add(ImportIssue(path, 'must be an object'));
      return null;
    }
    final m = Map<String, dynamic>.from(raw);
    final name = (m['name'] ?? '').toString().trim();
    if (name.isEmpty) {
      issues.add(ImportIssue('$path.name', 'is required'));
      return null;
    }
    final days = PlanDays.parse(m['days'] ?? m['daysOfWeek']);
    if (days == null) {
      issues.add(ImportIssue('$path.days', 'use weekday names like ["mon","tue"] or "weekdays"'));
    }
    final blocks = <ImportBlock>[];
    final rawBlocks = m['blocks'];
    if (rawBlocks is List) {
      for (var i = 0; i < rawBlocks.length; i++) {
        final b = _parseBlock(rawBlocks[i], '$path.blocks[$i]', issues);
        if (b != null) blocks.add(b);
      }
    } else {
      issues.add(ImportIssue('$path.blocks', 'is required and must be a list'));
    }
    for (final b in blocks) {
      if (b.durationMinutes < 30) {
        issues.add(ImportIssue(
          path,
          '"${b.label}" is shorter than the 30-minute grid and may be merged into a neighbour; short daily rituals belong in habits.',
          isError: false,
        ));
      }
      if (days != null && days.isNotEmpty && b.days.isNotEmpty && !b.days.any(days.contains)) {
        issues.add(ImportIssue(path, '"${b.label}" has days that are not in the template days', isError: false));
      }
    }
    return ImportTemplate(name: name, days: days ?? const [], blocks: blocks);
  }

  static ImportBlock? _parseBlock(dynamic raw, String path, List<ImportIssue> issues) {
    if (raw is! Map) {
      issues.add(ImportIssue(path, 'must be an object'));
      return null;
    }
    final m = Map<String, dynamic>.from(raw);
    final start = _time(m['start'], '$path.start', issues, required: true);
    final end = _time(m['end'], '$path.end', issues, required: true);
    final activity = (m['activity'] ?? '').toString().trim();
    if (activity.isEmpty) {
      issues.add(ImportIssue('$path.activity', 'is required'));
    }
    if (start == null || end == null || activity.isEmpty) return null;
    if (start == end) {
      issues.add(ImportIssue(path, 'start and end are the same'));
      return null;
    }
    final days = PlanDays.parse(m['days']);
    if (days == null) {
      issues.add(ImportIssue('$path.days', 'use weekday names like ["mon","wed","fri"]'));
    }
    return ImportBlock(
      start: start,
      end: end,
      activity: activity,
      note: (m['note'] ?? m['notes'] ?? '').toString().trim(),
      locked: m['locked'] == true || m['anchor'] == true,
      workBlock: m['workBlock'] == true || m['work'] == true,
      days: days ?? const [],
    );
  }

  static ImportTask? _parseTask(dynamic raw, String path, List<ImportIssue> issues, List<String> folders) {
    if (raw is String) {
      final t = raw.trim();
      if (t.isEmpty) return null;
      return ImportTask(title: t);
    }
    if (raw is! Map) {
      issues.add(ImportIssue(path, 'must be an object or a string'));
      return null;
    }
    final m = Map<String, dynamic>.from(raw);
    final title = (m['title'] ?? m['name'] ?? '').toString().trim();
    if (title.isEmpty) {
      issues.add(ImportIssue('$path.title', 'is required'));
      return null;
    }
    int? minutes;
    final rawMin = m['estimatedMinutes'] ?? m['minutes'];
    if (rawMin != null) {
      if (rawMin is num && rawMin > 0) {
        minutes = rawMin.round();
      } else {
        issues.add(ImportIssue('$path.estimatedMinutes', 'must be a positive number of minutes'));
      }
    }
    String? repeat;
    if (m['repeat'] != null) {
      repeat = TaskRepeat.normalize(m['repeat'].toString());
      if (repeat == null) {
        issues.add(ImportIssue('$path.repeat', '"${m['repeat']}" — use daily, weekdays, weekly:sun or monthly:15'));
      }
    }
    DateTime? scheduled;
    if (m['scheduledDate'] != null || m['date'] != null) {
      final s = (m['scheduledDate'] ?? m['date']).toString();
      scheduled = DateTime.tryParse(s);
      if (scheduled == null) {
        issues.add(ImportIssue('$path.scheduledDate', '"$s" must be yyyy-MM-dd'));
      }
    }
    final folder = (m['folder'] as String?)?.trim();
    if (folder != null && folder.isNotEmpty && folders.isNotEmpty && !folders.contains(folder)) {
      issues.add(ImportIssue('$path.folder', '"$folder" is not in folders; it will be created', isError: false));
    }
    return ImportTask(
      title: title,
      folder: folder == null || folder.isEmpty ? null : folder,
      estimatedMinutes: minutes,
      notes: (m['notes'] ?? '').toString().trim(),
      repeat: repeat,
      today: m['today'] == true,
      scheduledDate: scheduled,
      activity: (m['activity'] as String?)?.trim(),
    );
  }

  static void _checkDuplicates(Iterable<String> names, String path, List<ImportIssue> issues) {
    final seen = <String>{};
    for (final n in names) {
      final k = n.toLowerCase();
      if (!seen.add(k)) issues.add(ImportIssue(path, 'duplicate name "$n"'));
    }
  }

  static void _checkTemplateDayOverlap(List<ImportTemplate> templates, List<ImportIssue> issues) {
    final owner = <int, String>{};
    for (final t in templates) {
      for (final d in t.days) {
        final prev = owner[d];
        if (prev != null) {
          issues.add(ImportIssue('templates',
              '${PlanDays.shortNames[d - 1]} is claimed by both "$prev" and "${t.name}"; a day can only auto-apply one template'));
        } else {
          owner[d] = t.name;
        }
      }
    }
  }
}

/// A resolved 30/60-minute template slot ready to be written as a template
/// entry (`HHmm` document).
class TemplateSlot {
  final int hour;
  final int minute; // 0 or 30
  final int durationMinutes; // 60 or 30
  final String activity;
  final String note;
  final bool locked;
  final bool workBlock;

  const TemplateSlot({
    required this.hour,
    required this.minute,
    required this.durationMinutes,
    required this.activity,
    this.note = '',
    this.locked = false,
    this.workBlock = false,
  });

  String get id => '${hour.toString().padLeft(2, '0')}${minute.toString().padLeft(2, '0')}';
  bool get isEmpty => activity.isEmpty;

  Map<String, dynamic> toEntryMap() => {
        'planactivity': activity,
        'planNotes': note,
        'activity': activity == 'Sleep' ? 'Sleep' : '',
        'notes': '',
        'locked': locked,
        'workBlock': workBlock,
      };
}

/// A template after per-block day rules have been expanded: one concrete
/// slot list that applies to [days].
class ResolvedTemplate {
  final String name;
  final List<int> days;
  final List<TemplateSlot> slots;
  const ResolvedTemplate({required this.name, required this.days, required this.slots});
}

/// Turns free-form blocks into the app's 30-minute slot grid.
class TemplateSlotResolver {
  TemplateSlotResolver._();

  /// Expands a template into one [ResolvedTemplate] per distinct set of
  /// applicable blocks. A template whose blocks have no per-day rules yields
  /// exactly one result; one with e.g. Mon/Wed/Fri workouts yields two.
  static List<ResolvedTemplate> expand(ImportTemplate t) {
    if (t.days.isEmpty || t.blocks.every((b) => b.days.isEmpty)) {
      return [ResolvedTemplate(name: t.name, days: t.days, slots: resolve(t.blocks))];
    }
    final groups = <String, List<int>>{};
    for (final d in t.days) {
      final sig = [
        for (var i = 0; i < t.blocks.length; i++)
          if (t.blocks[i].appliesOn(d)) i
      ].join(',');
      groups.putIfAbsent(sig, () => []).add(d);
    }
    if (groups.length == 1) {
      return [ResolvedTemplate(name: t.name, days: t.days, slots: resolve(t.blocks, weekday: t.days.first))];
    }
    return groups.values
        .map((days) => ResolvedTemplate(
              name: '${t.name} (${PlanDays.label(days)})',
              days: days,
              slots: resolve(t.blocks, weekday: days.first),
            ))
        .toList();
  }

  /// Assigns each half-hour cell to the block covering most of it, then
  /// merges hours whose halves agree into single 60-minute slots.
  static List<TemplateSlot> resolve(List<ImportBlock> blocks, {int? weekday}) {
    final applicable = blocks.where((b) => b.appliesOn(weekday)).toList();
    final cells = List<ImportBlock?>.filled(48, null);
    final cellOverlap = List<int>.filled(48, 0);

    for (final b in applicable) {
      final ranges = b.end > b.start ? [(b.start, b.end)] : [(b.start, 1440), (0, b.end)];
      for (final (rs, re) in ranges) {
        final firstCell = rs ~/ 30;
        final lastCell = (re - 1) ~/ 30;
        for (var c = firstCell; c <= lastCell && c < 48; c++) {
          final cs = c * 30, ce = cs + 30;
          final overlap = (re < ce ? re : ce) - (rs > cs ? rs : cs);
          if (overlap <= 0) continue;
          if (overlap > cellOverlap[c] || (overlap == cellOverlap[c] && cells[c] != null && b.start > cells[c]!.start)) {
            cells[c] = b;
            cellOverlap[c] = overlap;
          }
        }
      }
    }

    final out = <TemplateSlot>[];
    for (var h = 0; h < 24; h++) {
      final a = cells[h * 2], b = cells[h * 2 + 1];
      if (a == null && b == null) continue;
      if (identical(a, b)) {
        out.add(_slot(h, 0, 60, a!));
        continue;
      }
      out.add(a == null
          ? TemplateSlot(hour: h, minute: 0, durationMinutes: 30, activity: '')
          : _slot(h, 0, 30, a));
      out.add(b == null
          ? TemplateSlot(hour: h, minute: 30, durationMinutes: 30, activity: '')
          : _slot(h, 30, 30, b));
    }
    return out;
  }

  static TemplateSlot _slot(int h, int m, int dur, ImportBlock b) => TemplateSlot(
        hour: h,
        minute: m,
        durationMinutes: dur,
        activity: b.activity,
        note: b.note,
        locked: b.locked,
        workBlock: b.workBlock,
      );
}
