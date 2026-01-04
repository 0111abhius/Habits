import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../models/timeline_entry.dart';
import '../main.dart';
import '../utils/activities.dart';
import '../utils/ai_service.dart';

class TemplateScreen extends StatefulWidget {
  final String? templateId;
  final String? templateName;
  const TemplateScreen({Key? key, this.templateId, this.templateName}) : super(key: key);

  @override
  State<TemplateScreen> createState() => _TemplateScreenState();
}

class _TemplateScreenState extends State<TemplateScreen> {
  // active template entries keyed by HHmm string
  Map<String, TimelineEntry> _entries = {};
  Set<int> _splitHours = {};
  final Map<String, TextEditingController> _noteCtrls = {};
  bool _pushing=false;

  List<String> _activities = List.from(kDefaultActivities);

  List<String> _flattenCats() => _activities;
  String _displayLabel(String c)=>displayActivity(c);

  @override
  void initState() {
    super.initState();
    _loadTemplate();
    _loadActivities();
  }

  @override
  void dispose() {
    for (final c in _noteCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _id(int hour, int minute) => '${hour.toString().padLeft(2, '0')}${minute.toString().padLeft(2, '0')}';

  Future<void> _loadTemplate() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    CollectionReference coll;
    if (widget.templateId != null) {
      coll = getFirestore()
          .collection('user_templates')
          .doc(uid)
          .collection('templates')
          .doc(widget.templateId)
          .collection('entries');
    } else {
      // Fallback for legacy calls (should be avoided)
      coll = getFirestore()
          .collection('template_entries')
          .doc(uid)
          .collection('entries');
    }

    final snapshot = await coll.get();
    final map = <String, TimelineEntry>{};
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final hour = int.parse(doc.id.substring(0, 2));
      final minute = int.parse(doc.id.substring(2));
      final start = DateTime(2000, 1, 1, hour, minute);
      map[doc.id] = TimelineEntry(
        id: doc.id,
        userId: uid,
        date: DateTime(2000),
        startTime: start,
        endTime: start.add(Duration(minutes: minute == 0 ? 60 : 30)),
        planactivity: data['planactivity'] ?? data['activity'] ?? '',
        planNotes: data['planNotes'] ?? data['notes'] ?? '',
        activity: data['activity'] ?? '',
        notes: data['notes'] ?? '',
      );
      if (minute == 30) _splitHours.add(hour);
    }
    setState(() => _entries = map);

    if (map.isEmpty) {
      await _generateSleepTemplate(uid);
    }
  }

  Future<void> _saveEntry(TimelineEntry entry) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    CollectionReference coll;
    if (widget.templateId != null) {
      coll = getFirestore()
          .collection('user_templates')
          .doc(uid)
          .collection('templates')
          .doc(widget.templateId)
          .collection('entries');
    } else {
      coll = getFirestore()
          .collection('template_entries')
          .doc(uid)
          .collection('entries');
    }

    await coll
        .doc(entry.id)
        .set({
      'planactivity': entry.planactivity,
      'planNotes': entry.planNotes,
      'activity': entry.activity,
      'notes': entry.notes,
    });
  }

  Future<void> _toggleSplit(int hour) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    CollectionReference coll;
    if (widget.templateId != null) {
      coll = getFirestore()
          .collection('user_templates')
          .doc(uid)
          .collection('templates')
          .doc(widget.templateId)
          .collection('entries');
    } else {
      coll = getFirestore().collection('template_entries').doc(uid).collection('entries');
    }

    if (_splitHours.contains(hour)) {
      // merge -> delete 30 entry
      final id30 = _id(hour, 30);
      await coll.doc(id30).delete();
      _entries.remove(id30);
      _splitHours.remove(hour);
    } else {
      // split -> add blank 30 entry
      final id30 = _id(hour, 30);
      final start = DateTime(2000, 1, 1, hour, 30);
      final entry = TimelineEntry(
        id: id30,
        userId: uid,
        date: DateTime(2000),
        startTime: start,
        endTime: start.add(const Duration(minutes: 30)),
        planactivity: '',
        planNotes: '',
        activity: '',
        notes: '',
      );
      _entries[id30] = entry;
      await _saveEntry(entry);
      _splitHours.add(hour);
    }
    if (mounted) setState(() {});
  }

  Widget _buildSubBlock(int hour, int minute) {
    final id = _id(hour, minute);
    final entry = _entries[id] ?? TimelineEntry(
      id: id,
      userId: FirebaseAuth.instance.currentUser?.uid ?? '',
      date: DateTime(2000),
      startTime: DateTime(2000,1,1,hour,minute),
      endTime: DateTime(2000,1,1,hour,minute).add(Duration(minutes: minute==0?60:30)),
      planactivity: '',
      planNotes: '',
      activity: '',
      notes: '',
    );

    _entries[id] = entry; // ensure present

    final ctrl = _noteCtrls.putIfAbsent(id, () => TextEditingController(text: entry.notes));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButton<String>(
            value: entry.planactivity.isEmpty ? null : entry.planactivity,
            hint: const Text('Select activity'),
            items: [
              const DropdownMenuItem(value: '', child: Text('— None —')),
            ]
              ..addAll(_flattenCats()
                  .map((c) => DropdownMenuItem(value: c, child: Text(_displayLabel(c))))
                  .toList()),
            onChanged: (val) async {
              if (val == null) return;
              final updated = TimelineEntry(
                id: entry.id,
                userId: entry.userId,
                date: entry.date,
                startTime: entry.startTime,
                endTime: entry.endTime,
                planactivity: val,
                planNotes: entry.planNotes,
                activity: val,
                notes: entry.notes,
              );
              _entries[id] = updated;
              await _saveEntry(updated);
              if (mounted) setState(() {});
            },
          ),
          // Notes are optional for template; keep UI minimal. Commented out.
          /*TextField(
            controller: ctrl,
            maxLines: null,
            decoration: const InputDecoration(hintText:'Notes',border:InputBorder.none),
            onChanged: (val) {
              final updated = TimelineEntry(
                id: entry.id,
                userId: entry.userId,
                date: entry.date,
                startTime: entry.startTime,
                endTime: entry.endTime,
                activity: entry.activity,
                notes: val,
              );
              _entries[id] = updated;
              _saveEntry(updated);
            },
          ),*/
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.templateName ?? 'Template'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI Coach',
            onPressed: _showAIAssistDialog,
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: 24,
        itemBuilder: (ctx,hour){
          return Card(
            margin: const EdgeInsets.symmetric(horizontal:8,vertical:4),
            child: Column(
              children: [
                ListTile(
                  title: Text('${hour.toString().padLeft(2,'0')}:00'),
                  trailing: IconButton(
                    icon: Icon(_splitHours.contains(hour)?Icons.call_merge:Icons.call_split),
                    onPressed: ()=>_toggleSplit(hour),
                  ),
                ),
                _buildSubBlock(hour,0),
                if(_splitHours.contains(hour)) _buildSubBlock(hour,30),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pushing?null:_pushTemplateToFuture,
        icon: const Icon(Icons.send),
        label: _pushing?const Text('Pushing...'):const Text('Push to future'),
      ),
    );
  }

  Future<void> _generateSleepTemplate(String uid) async {
    // fetch sleep settings
    final settingsDoc = await getFirestore().collection('user_settings').doc(uid).get();
    String sleepTxt = '23:00';
    String wakeTxt = '07:00';
    if (settingsDoc.exists) {
      final data = settingsDoc.data()!;
      sleepTxt = data['sleepTime'] ?? sleepTxt;
      wakeTxt = data['wakeTime'] ?? wakeTxt;
    }
    TimeOfDay _parse(String s) {
      final parts = s.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
    final sleepTime = _parse(sleepTxt);
    final wakeTime = _parse(wakeTxt);

    bool _isSleepHour(int hour) {
      if (sleepTime.hour < wakeTime.hour) {
        return hour >= sleepTime.hour && hour < wakeTime.hour;
      } else {
        return hour >= sleepTime.hour || hour < wakeTime.hour;
      }
    }

    final batch = getFirestore().batch();
    CollectionReference coll;
    if (widget.templateId != null) {
      coll = getFirestore()
          .collection('user_templates')
          .doc(uid)
          .collection('templates')
          .doc(widget.templateId)
          .collection('entries');
    } else {
      coll = getFirestore().collection('template_entries').doc(uid).collection('entries');
    }
    for (var hour = 0; hour < 24; hour++) {
      if (_isSleepHour(hour)) {
        final id = _id(hour, 0);
        final start = DateTime(2000, 1, 1, hour);
        final entry = TimelineEntry(
          id: id,
          userId: uid,
          date: DateTime(2000),
          startTime: start,
          endTime: start.add(const Duration(hours: 1)),
          planactivity: 'Sleep',
          planNotes: '',
          activity: 'Sleep',
          notes: '',
        );
        _entries[id] = entry;
        batch.set(coll.doc(id), {
          'planactivity': 'Sleep',
          'planNotes': '',
          'activity': 'Sleep',
          'notes': '',
        });
      }
    }
    await batch.commit();
    if (mounted) setState(() {});
  }

  Future<void> _pushTemplateToFuture() async {
    final uid = FirebaseAuth.instance.currentUser?.uid; if(uid==null) return;
    setState(()=>_pushing=true);
    try{
      // fetch template docs once
      QuerySnapshot tmplSnap;
      List<int>? validDays;
      if (widget.templateId != null) {
        tmplSnap = await getFirestore()
            .collection('user_templates')
            .doc(uid)
            .collection('templates')
            .doc(widget.templateId)
            .collection('entries')
            .get();
        // also get template days
        final tmplDoc = await getFirestore().collection('user_templates').doc(uid).collection('templates').doc(widget.templateId).get();
        if(tmplDoc.exists){
           validDays = List<int>.from(tmplDoc.data()!['daysOfWeek']??[]);
        }
      } else {
        tmplSnap = await getFirestore().collection('template_entries').doc(uid).collection('entries').get();
      }

      if(tmplSnap.docs.isEmpty){
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Template is empty')));
        return;
      }

      final now = DateTime.now();
      const int daysAhead=30;
      for(int d=1; d<=daysAhead; d++){
        final date = now.add(Duration(days:d));
        if (validDays != null && !validDays.contains(date.weekday)) continue; // Skip if not applicable

        final dateStr = '${date.year.toString().padLeft(4,'0')}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
        final entriesColl = getFirestore().collection('timeline_entries').doc(uid).collection('entries');

        WriteBatch batch = getFirestore().batch();
        for(final doc in tmplSnap.docs){
          final hour=int.parse(doc.id.substring(0,2));
          final minute=int.parse(doc.id.substring(2));
          final start = DateTime(date.year,date.month,date.day,hour,minute);
          final id = DateFormat('yyyyMMdd_HHmm').format(start);
          final data = doc.data() as Map<String, dynamic>;
          final tmplPlanCat = data['planactivity'] ?? data['activity'] ?? '';
          final tmplPlanNotes = data['planNotes'] ?? data['notes'] ?? '';
          final tmplRetroCat  = (data['activity'] ?? '') == 'Sleep' ? 'Sleep' : '';
          final tmplRetroNotes = tmplRetroCat.isNotEmpty ? (data['notes'] ?? '') : '';

          batch.set(entriesColl.doc(id),{
            'userId':uid,
            'date':dateStr,
            'hour':hour,
            'startTime':Timestamp.fromDate(start),
            'endTime':Timestamp.fromDate(start.add(Duration(minutes:minute==0?60:30))),
            'planactivity':tmplPlanCat,
            'planNotes':tmplPlanNotes,
            'activity':tmplRetroCat,
            'notes':tmplRetroNotes,
          });
        }
        await batch.commit();
      }
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Template applied to future days')));
    }catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Failed to push template')));
    }finally{
      if(mounted) setState(()=>_pushing=false);
    }
  }

  Future<void> _showAIAssistDialog() async {
    final TextEditingController goalCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI Template Coach'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('What is your main goal for this day?'),
            const SizedBox(height: 16),
            TextField(
              controller: goalCtrl,
              decoration: const InputDecoration(
                labelText: 'Goal (e.g., "Deep work", "Recovery")',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _generateTemplateInsights(goalCtrl.text.trim());
            },
            child: const Text('Get Suggestions'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateTemplateInsights(String goal) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final tmplStr = _getTemplateString();
      final aiService = AIService();
      final suggestions = await aiService.getTemplateSuggestions(
        currentTemplate: tmplStr.isEmpty ? '(Empty Template)' : tmplStr,
        goal: goal.isEmpty ? 'General Productivity' : goal,
      );

      if (mounted) {
        Navigator.pop(context); // loading
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('AI Suggestions'),
            content: SingleChildScrollView(
              child: Text(suggestions),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  String _getTemplateString() {
    final sortedKeys = _entries.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final key in sortedKeys) {
      final entry = _entries[key]!;
      final act = entry.planactivity.isEmpty ? entry.activity : entry.planactivity;
      if (act.isNotEmpty) {
        final hour = key.substring(0, 2);
        final minute = key.substring(2);
        buffer.writeln('$hour:$minute - $act');
      }
    }
    return buffer.toString();
  }
  Future<void> _loadActivities() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await getFirestore().collection('user_settings').doc(uid).get();
    if (!doc.exists) return;
    final data = doc.data()!;
    final List<String> custom = List<String>.from(data['customActivities'] ?? []);
    final List<String> archived = List<String>.from(data['archivedActivities'] ?? []);
    final Set<String> all = {...kDefaultActivities, ...custom}..removeAll(archived);
    setState(() {
      _activities = all.toList();
    });
  }
} 