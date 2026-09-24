/// Human/LLM-facing description of the import format plus the prompt users
/// paste into any LLM together with their plan.
class PlanImportPrompt {
  PlanImportPrompt._();

  static const String schema = r'''
{
  "version": 1,
  "settings": {
    "wakeTime": "07:00",
    "sleepTime": "23:00",
    "goal": "One sentence: what a good day looks like.",
    "topTasksLimit": 3,
    "reminders": { "enabled": true, "planTomorrow": "16:30", "morningPlan": "08:30", "eveningLog": "21:30" }
  },
  "activities": ["Deep Work", "Planning", "Meeting", "Family", "Wind-down"],
  "folders": ["Work", "Life admin", "Job search", "Routines"],
  "folderActivities": { "Work": "Deep Work", "Life admin": "Other" },
  "habits": [
    { "name": "Meditation", "type": "binary", "frequency": "daily", "tier": 1, "reminder": "07:20" },
    { "name": "Workout", "type": "binary", "frequency": "weekly", "weeklyTarget": 3, "tier": 2 },
    { "name": "Water", "type": "counter", "frequency": "daily", "targetCount": 8 }
  ],
  "templates": [
    {
      "name": "Office weekday",
      "days": ["mon", "tue", "wed", "thu", "fri"],
      "blocks": [
        { "start": "23:00", "end": "07:00", "activity": "Sleep", "locked": true },
        { "start": "07:40", "end": "08:10", "activity": "Exercise", "days": ["mon", "wed", "fri"] },
        { "start": "08:30", "end": "08:40", "activity": "Planning", "note": "Anchor 1 - morning launch", "locked": true },
        { "start": "08:40", "end": "10:00", "activity": "Deep Work", "workBlock": true },
        { "start": "10:00", "end": "11:00", "activity": "Meeting", "note": "Standing meeting", "locked": true },
        { "start": "11:30", "end": "16:30", "activity": "Work", "workBlock": true },
        { "start": "16:30", "end": "17:30", "activity": "Planning", "note": "Anchor 2 - shutdown", "locked": true },
        { "start": "18:00", "end": "19:30", "activity": "Family" },
        { "start": "21:30", "end": "22:00", "activity": "Wind-down", "note": "Anchor 3", "locked": true }
      ]
    },
    { "name": "Work from home", "days": [], "blocks": [] },
    { "name": "Saturday", "days": ["sat"], "blocks": [] }
  ],
  "tasks": [
    { "title": "Weekly reset", "folder": "Routines", "estimatedMinutes": 30, "repeat": "weekly:sun" },
    { "title": "Book mom's flight change", "folder": "Life admin", "estimatedMinutes": 20, "today": true }
  ]
}
''';

  static const String rules = '''
Rules for the JSON
- Times are 24h "HH:mm". Weekdays are "mon".."sun" (or "weekdays" / "weekend").
- The timeline is a 30-minute grid. Blocks shorter than 30 minutes get merged into a neighbour, so put short daily rituals (meditation, speech practice, journaling) into "habits", not "blocks".
- A block crossing midnight (Sleep) uses end < start, e.g. 23:00 -> 07:00.
- "locked": true marks an anchor. Planners will never overwrite it.
- "workBlock": true marks flexible work time. The app places the day's top tasks into these blocks by estimate.
- A block with its own "days" applies only on those days (e.g. workouts Mon/Wed/Fri). The app will split the template automatically.
- Each weekday may belong to at most one template with "days". Templates with "days": [] are applied manually (e.g. a work-from-home variant).
- Habits: "type" is "binary" or "counter"; "frequency" is "daily" or "weekly" with "weeklyTarget" 1-7; "tier" 1 = daily & protected, 2 = a few times a week, 3 = seasonal.
- Tasks: "repeat" is one of daily, weekdays, weekly:sun, weekly:mon,wed, monthly:15. Leave out one-off ideas that are not real tasks.
- Activities not listed in "activities" are created automatically from the blocks. Keep names short (max ~16 characters) and reuse them across blocks.
- Do not include phone rules, if-then plans or prose; those stay in the plan document. Omit any section you have no data for.
- Output only the JSON object, no commentary.
''';

  /// Full prompt: paste into any LLM together with the plan text.
  static String buildPrompt({List<String> existingActivities = const [], List<String> existingFolders = const []}) {
    final buf = StringBuffer();
    buf.writeln('You convert a personal daily-routine plan into the import format of the "Day Coach" app.');
    buf.writeln('Read the plan below and produce ONE JSON object following this template (fields are optional unless the rules say otherwise):');
    buf.writeln();
    buf.writeln(schema.trim());
    buf.writeln();
    buf.writeln(rules.trim());
    if (existingActivities.isNotEmpty) {
      buf.writeln();
      buf.writeln('The app already has these activities; prefer them when they fit: ${existingActivities.join(', ')}.');
    }
    if (existingFolders.isNotEmpty) {
      buf.writeln('Existing task folders: ${existingFolders.join(', ')}.');
    }
    buf.writeln();
    buf.writeln('If something in the plan cannot be represented, drop it rather than inventing fields.');
    buf.writeln();
    buf.writeln('PLAN:');
    buf.writeln('<paste your plan here>');
    return buf.toString();
  }
}
