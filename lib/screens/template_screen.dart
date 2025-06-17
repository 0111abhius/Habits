import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../models/timeline_entry.dart';
import '../main.dart';

class TemplateScreen extends StatefulWidget {
  const TemplateScreen({Key? key}) : super(key: key);

  @override
  State<TemplateScreen> createState() => _TemplateScreenState();
}

class _TemplateScreenState extends State<TemplateScreen> {
  // active template entries keyed by HHmm string
  Map<String, TimelineEntry> _entries = {};
  Set<int> _splitHours = {};
  final Map<String, TextEditingController> _noteCtrls = {};

  // Categories helpers (reuse minimal copy from timeline)
  static const List<String> _initialCategories = [
    'Sleep',
    'Work',
    'Exercise',
    'Study',
    'Social',
    'Hobby',
    'Other'
  ];
  List<String> _categories = List.from(_initialCategories);

  List<String> _flattenCats() => _categories;

  @override
  void initState() {
    super.initState();
    _loadTemplate();
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
    final snapshot = await getFirestore()
        .collection('template_entries')
        .doc(uid)
        .collection('entries')
        .get();
    final map = <String, TimelineEntry>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final hour = int.parse(doc.id.substring(0, 2));
      final minute = int.parse(doc.id.substring(2));
      final start = DateTime(2000, 1, 1, hour, minute);
      map[doc.id] = TimelineEntry(
        id: doc.id,
        userId: uid,
        date: DateTime(2000),
        startTime: start,
        endTime: start.add(Duration(minutes: minute == 0 ? 60 : 30)),
        category: data['category'] ?? '',
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
    await getFirestore()
        .collection('template_entries')
        .doc(uid)
        .collection('entries')
        .doc(entry.id)
        .set({
      'category': entry.category,
      'notes': entry.notes,
    });
  }

  Future<void> _toggleSplit(int hour) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final coll = getFirestore().collection('template_entries').doc(uid).collection('entries');

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
        category: '',
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
      category: '',
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
            value: entry.category.isEmpty ? null : entry.category,
            hint: const Text('Select category'),
            items: _flattenCats().map((c)=>DropdownMenuItem(value:c,child:Text(c))).toList(),
            onChanged: (val) async {
              if (val == null) return;
              final updated = TimelineEntry(
                id: entry.id,
                userId: entry.userId,
                date: entry.date,
                startTime: entry.startTime,
                endTime: entry.endTime,
                category: val,
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
                category: entry.category,
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
        title: const Text('Template'),
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
    final coll = getFirestore().collection('template_entries').doc(uid).collection('entries');
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
          category: 'Sleep',
          notes: '',
        );
        _entries[id] = entry;
        batch.set(coll.doc(id), {'category': 'Sleep', 'notes': ''});
      }
    }
    await batch.commit();
    if (mounted) setState(() {});
  }
} 