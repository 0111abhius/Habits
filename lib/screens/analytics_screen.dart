import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../widgets/ai_chat_dialog.dart';
import '../utils/ai_service.dart';
import '../models/timeline_entry.dart';
import '../main.dart';
import '../models/habit.dart';
import '../utils/ai_service.dart';

enum AnalyticsRange {
  daily,
  weekly,
  monthly,
  custom,
}

class _HabitStat {
  final String name;
  final HabitType type;
  final double completionRate; // for binary [0..1]
  final double avgCount; // for counter
  final int daysLogged;

  _HabitStat.binary({required this.name, required double rate})
      : type = HabitType.binary,
        completionRate = rate,
        avgCount = 0,
        daysLogged = 0;

  _HabitStat.counter({required this.name, required this.avgCount, required this.daysLogged})
      : type = HabitType.counter,
        completionRate = 0;
}

class _AnalyticsData {
  final Map<String, double> activityAvg; // hours per day
  final List<_HabitStat> habits;
  final int days;

  _AnalyticsData({required this.activityAvg, required this.habits, required this.days});
}

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  AnalyticsRange _selectedRange = AnalyticsRange.daily;
  DateTime _anchorDate = DateTime.now(); // used for daily/weekly/monthly
  DateTimeRange? _customRange;
  Future<_AnalyticsData>? _futureData;

  @override
  void initState() {
    super.initState();
    _futureData = _fetchData();
  }

  DateTime _startOfWeek(DateTime d) => d.subtract(Duration(days: d.weekday - 1)); // Monday
  DateTime _endOfWeek(DateTime d) => _startOfWeek(d).add(const Duration(days: 6));

  DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);

  Future<_AnalyticsData> _fetchData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _AnalyticsData(activityAvg: {}, habits: [], days: 0);

    DateTime start;
    DateTime end;
    switch (_selectedRange) {
      case AnalyticsRange.daily:
        start = DateTime(_anchorDate.year, _anchorDate.month, _anchorDate.day);
        end = start;
        break;
      case AnalyticsRange.weekly:
        final now = DateTime.now();
        end = DateTime(now.year, now.month, now.day);
        start = end.subtract(const Duration(days: 6)); // last 7 days including today
        break;
      case AnalyticsRange.monthly:
        final nowM = DateTime.now();
        end = DateTime(nowM.year, nowM.month, nowM.day);
        start = _startOfMonth(end); // first day of current month
        break;
      case AnalyticsRange.custom:
        if (_customRange == null) return _AnalyticsData(activityAvg: {}, habits: [], days: 0);
        start = _customRange!.start;
        end = _customRange!.end;
        break;
    }

    // Clamp end to today (no future)
    final today = DateTime.now();
    if (end.isAfter(DateTime(today.year, today.month, today.day))) {
      end = DateTime(today.year, today.month, today.day);
    }

    final dateFormat = DateFormat('yyyy-MM-dd');

    // fetch completed-day docs
    final completedSnap = await getFirestore()
        .collection('daily_logs')
        .doc(user.uid)
        .collection('logs')
        .where('date', isGreaterThanOrEqualTo: dateFormat.format(start))
        .where('date', isLessThanOrEqualTo: dateFormat.format(end))
        .get();

    final completedDates = {
      for (final d in completedSnap.docs) (d['date'] as String)
    };

    final days = completedDates.length;
    if(days==0){
      return _AnalyticsData(activityAvg:{},habits:[],days:0);
    }

    final startStr = dateFormat.format(start);
    final endStr = dateFormat.format(end);

    final snapshot = await getFirestore()
        .collection('timeline_entries')
        .doc(user.uid)
        .collection('entries')
        .where('date', isGreaterThanOrEqualTo: startStr)
        .where('date', isLessThanOrEqualTo: endStr)
        .get();

    final entries = snapshot.docs
        .map((doc) => TimelineEntry.fromFirestore(doc))
        .where((e) => completedDates.contains(dateFormat.format(e.date)))
        .toList();

    // Aggregate hours per activity (sum then convert to avg per day)
    final Map<String, double> totals = {};
    for (final entry in entries) {
      final durationHours = entry.endTime.difference(entry.startTime).inMinutes / 60.0;
      final cat = entry.activity.isEmpty ? 'Uncategorised' : entry.activity;
      totals[cat] = (totals[cat] ?? 0) + durationHours;
    }

    // convert to average hours per day
    final Map<String, double> avgPerDay = {for (var e in totals.entries) e.key: e.value / days};

    // -------- Habit analytics --------
    final habitsSnap = await getFirestore()
        .collection('habits')
        .doc(user.uid)
        .collection('habits')
        .get();

    final habitsList = habitsSnap.docs.map((d) => Habit.fromMap(d.id, d.data() as Map<String, dynamic>)).toList();

    // Prepare accumulators
    final Map<String, int> binaryCompleted = {};
    final Map<String, int> binaryLogged = {};
    final Map<String, int> counterSum = {};
    final Map<String, int> counterLogged = {};

    // Iterate over each day in range and fetch logs for that date.
    for (int offset = 0; offset < days; offset++) {
      final date = start.add(Duration(days: offset));
      final dateId = dateFormat.format(date);
      final logsSnap = await getFirestore()
          .collection('habit_logs')
          .doc(user.uid)
          .collection('dates')
          .doc(dateId)
          .collection('habits')
          .get();

      for (final doc in logsSnap.docs) {
        final value = (doc.data() as Map<String, dynamic>)['value'];
        final Habit? habit = habitsList.where((h) => h.id == doc.id).isNotEmpty
            ? habitsList.firstWhere((h) => h.id == doc.id)
            : null;
        if (habit == null) continue; // habit may have been deleted

        if (habit.type == HabitType.binary) {
          binaryLogged[habit.id] = (binaryLogged[habit.id] ?? 0) + 1;
          if (value == true) {
            binaryCompleted[habit.id] = (binaryCompleted[habit.id] ?? 0) + 1;
          }
        } else {
          if (value != null) {
            counterLogged[habit.id] = (counterLogged[habit.id] ?? 0) + 1;
            final int countVal = value is int ? value : int.tryParse(value.toString()) ?? 0;
            counterSum[habit.id] = (counterSum[habit.id] ?? 0) + countVal;
          }
        }
      }
    }

    final List<_HabitStat> habitStats = [];
    for (final h in habitsList) {
      if (h.type == HabitType.binary) {
        final logged = binaryLogged[h.id] ?? 0;
        final comp = binaryCompleted[h.id] ?? 0;
        final rate = logged == 0 ? 0.0 : comp / logged; // exclude not-logged days
        habitStats.add(_HabitStat.binary(name: h.name, rate: rate));
      } else {
        final sum = counterSum[h.id] ?? 0;
        final loggedDays = counterLogged[h.id] ?? 0;
        final avg = loggedDays == 0 ? 0.0 : sum / loggedDays;
        habitStats.add(_HabitStat.counter(name: h.name, avgCount: avg, daysLogged: loggedDays));
      }
    }

    return _AnalyticsData(activityAvg: avgPerDay, habits: habitStats, days: days);
  }

  Future<String> _fetchDetailedLogs(DateTime start, DateTime end) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';

    final dateFormat = DateFormat('yyyy-MM-dd');
    final timeFormat = DateFormat('HH:mm');
    final startStr = dateFormat.format(start);
    final endStr = dateFormat.format(end);

    final snapshot = await getFirestore()
        .collection('timeline_entries')
        .doc(user.uid)
        .collection('entries')
        .where('date', isGreaterThanOrEqualTo: startStr)
        .where('date', isLessThanOrEqualTo: endStr)
        .get();

    final docs = snapshot.docs;
    // Sort in memory to avoid Firestore Composite Index creation
    docs.sort((a, b) {
      final tA = (a.data()['startTime'] as Timestamp).toDate();
      final tB = (b.data()['startTime'] as Timestamp).toDate();
      return tA.compareTo(tB);
    });

    final StringBuffer buffer = StringBuffer();
    String currentDate = '';

    for (final doc in docs) {
      final entry = TimelineEntry.fromFirestore(doc);
      final dateStr = dateFormat.format(entry.date);
      
      if (dateStr != currentDate) {
        buffer.writeln('\nDate: $dateStr');
        currentDate = dateStr;
      }

      final timeRange = '${timeFormat.format(entry.startTime)} - ${timeFormat.format(entry.endTime)}';
      final activity = entry.activity.isEmpty ? 'Uncategorised' : entry.activity;
      final notes = entry.notes.isNotEmpty ? ' (${entry.notes})' : '';
      
      String line = '  $timeRange: Actual: $activity$notes';
      
      // Add Plan info if available
      if (entry.planactivity.isNotEmpty) {
        final planAct = entry.planactivity;
        final planNotes = entry.planNotes.isNotEmpty ? ' (${entry.planNotes})' : '';
        line += ' | Planned: $planAct$planNotes';
      }
      
      buffer.writeln(line);
    }

    return buffer.toString();
  }

  void _refreshStats() {
    setState(() {
      _futureData = _fetchData();
    });
  }

  Future<void> _pickAnchorDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchorDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _anchorDate = picked;
        _refreshStats();
      });
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: _customRange ?? DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _refreshStats();
      });
    }
  }

  String _rangeLabel() {
    final df = DateFormat('dd MMM yyyy');
    switch (_selectedRange) {
      case AnalyticsRange.daily:
        return df.format(_anchorDate);
      case AnalyticsRange.weekly:
        final now = DateTime.now();
        final end = DateTime(now.year, now.month, now.day);
        final start = end.subtract(const Duration(days: 6));
        return '${df.format(start)} - ${df.format(end)}';
      case AnalyticsRange.monthly:
        final nowM = DateTime.now();
        final mdf = DateFormat('MMMM yyyy');
        return mdf.format(nowM);
      case AnalyticsRange.custom:
        if (_customRange == null) return 'Select range';
        return '${df.format(_customRange!.start)} - ${df.format(_customRange!.end)}';
    }
  }

  Future<void> _showAIInsightsDialog() async {
    final TextEditingController goalCtrl = TextEditingController();
    
    // Calculate current range dates
    DateTime start, end;
    switch (_selectedRange) {
      case AnalyticsRange.daily:
        start = end = DateTime(_anchorDate.year, _anchorDate.month, _anchorDate.day);
        break;
      case AnalyticsRange.weekly:
        final now = DateTime.now();
        end = DateTime(now.year, now.month, now.day);
        start = end.subtract(const Duration(days: 6));
        break;
      case AnalyticsRange.monthly:
        final nowM = DateTime.now();
        end = DateTime(nowM.year, nowM.month, nowM.day);
        start = _startOfMonth(end);
        break;
      case AnalyticsRange.custom:
        if (_customRange == null) return;
        start = _customRange!.start;
        end = _customRange!.end;
        break;
    }

    // Checking if we are going too far back or asking too much data might be good, but let's trust the user/API limits for now.
    
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Get AI Insights'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter a specific goal or focus for the AI to analyze your schedule against.'),
            const SizedBox(height: 16),
            TextField(
              controller: goalCtrl,
              decoration: const InputDecoration(
                labelText: 'Goal (e.g., "Be more productive")',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _generateInsights(start, end, goalCtrl.text.trim());
            },
            child: const Text('Analyze'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateInsights(DateTime start, DateTime end, String goal) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final logs = await _fetchDetailedLogs(start, end);
      if (logs.isEmpty) {
        if (mounted) {
          Navigator.pop(context); // loading
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No logs found for this period to analyze.')));
        }
        return;
      }

      final aiService = AIService();
      // Prepare the initial prompt but don't send it yet; the dialog will handle "initChat".
      // Actually, AIChatDialog expects an initial prompt to fire off immediately as the "System/Context" message.
      
      final prompt = '''
You are a productivity expert. I will provide you with a log of my activities for a specific period and a goal I want to achieve.
Please analyze my schedule and provide specific, actionable suggestions.

GOAL: $goal

ACTIVITY LOGS:
$logs

Please keep the response concise, encouraging, and focused on the goal. 
Analyze the time gaps and activity choices.
Pay special attention to where my 'Actual' activity differed from my 'Planned' activity.
''';

      if (mounted) {
        Navigator.pop(context); // loading
        await showDialog(
          context: context,
          builder: (ctx) => AIChatDialog(
            title: 'AI Insights Chat',
            initialPrompt: prompt,
            chatSession: aiService.createChatSession(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // loading
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Get AI Insights',
            onPressed: _showAIInsightsDialog,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButton<AnalyticsRange>(
                    value: _selectedRange,
                    items: const [
                      DropdownMenuItem(value: AnalyticsRange.daily, child: Text('Daily')),
                      DropdownMenuItem(value: AnalyticsRange.weekly, child: Text('Weekly')),
                      DropdownMenuItem(value: AnalyticsRange.monthly, child: Text('Monthly')),
                      DropdownMenuItem(value: AnalyticsRange.custom, child: Text('Custom')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedRange = value;
                          _refreshStats();
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _selectedRange == AnalyticsRange.custom ? _pickCustomRange : _pickAnchorDate,
                  child: Text(_rangeLabel()),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<_AnalyticsData>(
                future: _futureData,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  final data = snapshot.data ?? _AnalyticsData(activityAvg: {}, habits: [], days: 0);
                  if (data.activityAvg.isEmpty) {
                    return const Center(child: Text('No data for selected range'));
                  }

                  final sorted = data.activityAvg.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value));

                  final double totalHours = data.activityAvg.values.fold(0, (a, b) => a + b);

                  return ListView(
                    children: [
                      ..._buildactivityTiles(sorted, totalHours),
                      ListTile(
                        title: const Text('Days logged in range'),
                        trailing: Text('${data.days}'),
                      ),
                      const Divider(),
                      ListTile(
                        title: const Text('Avg Tracked Time / Day'),
                        trailing: Text('${totalHours.toStringAsFixed(1)} h/day'),
                      ),
                      const SizedBox(height: 8),
                      _buildAdditionalStats(data.activityAvg),
                      if (data.habits.isNotEmpty) ...[
                        const Divider(),
                        const ListTile(title: Text('Habits')),
                        ...data.habits.map((h) => h.type == HabitType.binary
                            ? ListTile(
                                title: Text(h.name),
                                subtitle: LinearProgressIndicator(
                                  value: h.completionRate,
                                  minHeight: 6,
                                ),
                                trailing: Text('${(h.completionRate * 100).toStringAsFixed(0)}%'),
                              )
                            : ListTile(
                                title: Text(h.name),
                                trailing: Text('${h.avgCount.toStringAsFixed(1)} /day (${h.daysLogged}d)'),
                              )),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdditionalStats(Map<String, double> data) {
    if (data.isEmpty) return const SizedBox.shrink();

    final sleepHours = data['Sleep'] ?? 0;
    final otherActivities = Map.of(data)..remove('Sleep');
    String topCat = '';
    double topHours = 0;
    otherActivities.forEach((key, value) {
      if (value > topHours) {
        topCat = key;
        topHours = value;
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sleepHours > 0)
          ListTile(
            title: const Text('Total Sleep'),
            trailing: Text('${sleepHours.toStringAsFixed(1)} h'),
          ),
        if (topCat.isNotEmpty)
          ListTile(
            title: const Text('Top Activity'),
            subtitle: Text(topCat),
            trailing: Text('${topHours.toStringAsFixed(1)} h'),
          ),
      ],
    );
  }

  List<Widget> _buildactivityTiles(List<MapEntry<String, double>> sorted, double totalHours) {
    // group by parent
    final Map<String, double> parentTotals = {};
    final Map<String, Map<String,double>> childMap = {};
    for (final entry in sorted) {
      final parts = entry.key.split(' / ');
      final parent = parts.first;
      final isChild = parts.length > 1;
      parentTotals[parent] = (parentTotals[parent] ?? 0) + entry.value;
      if (isChild) {
        final child = parts[1];
        final map = childMap[parent] ?? {};
        map[child] = entry.value;
        childMap[parent] = map;
      }
    }

    final parentEntries = parentTotals.entries.toList()
      ..sort((a,b)=>b.value.compareTo(a.value));

    List<Widget> tiles=[];
    for (final p in parentEntries) {
      final children = childMap[p.key];
      if (children==null || children.isEmpty) {
        tiles.add(ListTile(
          title: Text(p.key),
          subtitle: LinearProgressIndicator(value:p.value/totalHours,minHeight:6),
          trailing: Text('${p.value.toStringAsFixed(1)} h/day'),
        ));
      } else {
        final childList = children.entries.toList()
          ..sort((a,b)=>b.value.compareTo(a.value));
        tiles.add(ExpansionTile(
          title: Row(
            children:[Expanded(child:Text(p.key)),Text('${p.value.toStringAsFixed(1)} h/day')],
          ),
          children: childList.map((c)=>ListTile(
            title: Text(c.key),
            subtitle: LinearProgressIndicator(value:c.value/totalHours,minHeight:4),
            trailing: Text('${c.value.toStringAsFixed(1)} h/day'),
          )).toList(),
        ));
      }
    }
    return tiles;
  }
} 