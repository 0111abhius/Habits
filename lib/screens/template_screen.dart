import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

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
      final jsonStr = await aiService.getTemplateSuggestions(
        currentTemplate: tmplStr.isEmpty ? '(Empty Template)' : tmplStr,
        goal: goal.isEmpty ? 'General Productivity' : goal,
        existingActivities: _activities,
      );

      if (!mounted) return;
      Navigator.pop(context); // loading

      try {
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        if (data.containsKey('error')) {
          _showError('AI Error: ${data['error']}');
          return;
        }
        _showReviewDialog(data);
      } catch (e) {
        // Fallback if not valid JSON (shouldn't happen with updated prompt, but safety first)
        _showError('Failed to parse AI response. Raw output:\n$jsonStr');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showError('Error: $e');
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showReviewDialog(Map<String, dynamic> data) async {
    final schedule = Map<String, String>.from(data['schedule'] ?? {});
    final newActs = List<String>.from(data['newActivities'] ?? []);
    final reasoning = data['reasoning'] ?? '';

    // Track selected new activities
    final Set<String> selectedNewActs = Set.from(newActs);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('AI Review'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: DefaultTabController(
              length: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const TabBar(
                    labelColor: Colors.blue,
                    tabs: [Tab(text: 'Schedule'), Tab(text: 'New Activities')],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Schedule Tab
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (reasoning.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text('Note: $reasoning', style: const TextStyle(fontStyle: FontStyle.italic)),
                                ),
                                const Divider(),
                              ],
                              ...schedule.entries.map((e) => ListTile(
                                dense: true,
                                title: Text(e.key),
                                subtitle: Text(e.value),
                              )),
                            ],
                          ),
                        ),
                        // New Activities Tab
                        newActs.isEmpty
                            ? const Center(child: Text('No new activities suggested.'))
                            : ListView(
                                shrinkWrap: true,
                                children: newActs.map((act) => CheckboxListTile(
                                  title: Text(act),
                                  value: selectedNewActs.contains(act),
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) selectedNewActs.add(act);
                                      else selectedNewActs.remove(act);
                                    });
                                  },
                                )).toList(),
                              ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _applyAISuggestions(schedule, selectedNewActs.toList());
              },
              child: const Text('Apply & Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyAISuggestions(Map<String, String> schedule, List<String> newActivities) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // 1. Create new activities if any
    if (newActivities.isNotEmpty) {
      final settingsRef = getFirestore().collection('user_settings').doc(uid);
      await getFirestore().runTransaction((tx) async {
        final doc = await tx.get(settingsRef);
        if (doc.exists) {
            final data = doc.data()!;
            final currentCustom = List<String>.from(data['customActivities'] ?? []);
            final currentArchived = List<String>.from(data['archivedActivities'] ?? []);
            
            // Add new ones, remove from archived if present
            for (final act in newActivities) {
                if (!currentCustom.contains(act)) currentCustom.add(act);
                if (currentArchived.contains(act)) currentArchived.remove(act);
            }
            tx.update(settingsRef, {
                'customActivities': currentCustom,
                'archivedActivities': currentArchived,
            });
        }
      });
      // Refresh local list
      await _loadActivities();
    }

    // 2. Apply schedule
    // We iterate over the schedule map "HH:mm" -> "Activity"
    // We assume 30 or 60 min blocks depending on existing splits? 
    // Actually, AI returns HH:mm. We should map strictly to our slots.
    // If AI gives "08:15", we likely can't handle it easily without sub-hour logic, so we assume HH:00 or HH:30.
    // We will parse HH and mm.
    
    // Clear current pushes or batch update? Using _entries update logic.
    // We'll process each schedule item.
    
    for (final entry in schedule.entries) {
      final parts = entry.key.split(':');
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      
      // Ensure split if minute is 30 and slot doesn't exist?
      // Or just find the closest slot. 
      // If m >= 30, use 30 slot. If m < 30, use 00 slot.
      // This is a simplification.
      
      final minute = m >= 30 ? 30 : 0;
      
      // If we need 30 but don't have split, toggle it
      if (minute == 30 && !_splitHours.contains(h)) {
         await _toggleSplit(h); 
      }
      
      final id = _id(h, minute);
      final currentEntry = _entries[id];
      if (currentEntry != null) {
          final updated = TimelineEntry(
            id: currentEntry.id,
            userId: currentEntry.userId,
            date: currentEntry.date,
            startTime: currentEntry.startTime,
            endTime: currentEntry.endTime,
            planactivity: entry.value, // Set as Planned Activity
            planNotes: currentEntry.planNotes,
            activity: entry.value, // Also set as default Activity? Maybe leave blank? Let's strict to Plan.
            notes: currentEntry.notes,
          );
          _entries[id] = updated;
          await _saveEntry(updated);
      }
    }
    
    if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI Suggestions applied!')));
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