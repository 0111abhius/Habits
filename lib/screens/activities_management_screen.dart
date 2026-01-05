import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart'; // for getFirestore()
import '../utils/activities.dart';

class ActivitiesManagementScreen extends StatefulWidget {
  const ActivitiesManagementScreen({super.key});

  @override
  State<ActivitiesManagementScreen> createState() => _ActivitiesManagementScreenState();
}

class _ActivitiesManagementScreenState extends State<ActivitiesManagementScreen> {
  List<String> _activities = [];
  List<String> _archived = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await getFirestore().collection('user_settings').doc(uid).get();
    if (doc.exists) {
      final data = doc.data()!;
      _activities = List<String>.from(data['customActivities'] ?? []);
      _archived = List<String>.from(data['archivedActivities'] ?? []);
    } else {
      _activities = List.from(kDefaultActivities);
      _archived = [];
    }
    
    // Sort alphabetically
    _activities.sort();
    _archived.sort();

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _renameOrMerge(String oldName, String newName) async {
    if (oldName == newName) return;
    
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_activities.contains(newName) ? 'Merge Activities?' : 'Rename Activity?'),
        content: Text(_activities.contains(newName) 
            ? 'Merge "$oldName" into existing "$newName"?\nThis will update all past entries and remove "$oldName".'
            : 'Rename "$oldName" to "$newName"?\nThis will update all past entries.'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_activities.contains(newName) ? 'Merge' : 'Rename'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final batch = getFirestore().batch();
      final userSettingsRef = getFirestore().collection('user_settings').doc(uid);

      // 1. Update Settings List
      // Remove old
      _activities.remove(oldName);
      _archived.remove(oldName); 
      // Add new if not present
      if (!_activities.contains(newName) && !_archived.contains(newName)) {
         _activities.add(newName);
         _activities.sort();
      }

      batch.set(userSettingsRef, {
        'customActivities': _activities,
        'archivedActivities': _archived,
      }, SetOptions(merge: true));

      // 2. Update Timeline Entries
      final timelineQuery = await getFirestore()
          .collection('timeline_entries')
          .doc(uid)
          .collection('entries')
          .where(Filter.or(
             Filter('activity', isEqualTo: oldName),
             Filter('planactivity', isEqualTo: oldName),
          ))
          .get();

      for (final doc in timelineQuery.docs) {
        final data = doc.data();
        final updates = <String, dynamic>{};
        if (data['activity'] == oldName) updates['activity'] = newName;
        if (data['planactivity'] == oldName) updates['planactivity'] = newName;
        batch.update(doc.reference, updates);
      }

      // 3. Update Templates (Legacy + New)
      // Legacy
      final legTmplQuery = await getFirestore()
          .collection('template_entries')
          .doc(uid)
          .collection('entries')
          .where(Filter.or(
             Filter('activity', isEqualTo: oldName),
             Filter('planactivity', isEqualTo: oldName),
          ))
          .get();
      
      for (final doc in legTmplQuery.docs) {
        final data = doc.data();
        final updates = <String, dynamic>{};
        if (data['activity'] == oldName) updates['activity'] = newName;
        if (data['planactivity'] == oldName) updates['planactivity'] = newName;
        batch.update(doc.reference, updates);
      }
      
      // New Templates (This is harder because they are sub-sub collections)
      // We first need to get all template IDs
      final templatesList = await getFirestore()
          .collection('user_templates')
          .doc(uid)
          .collection('templates')
          .get();
      
      for (final tmplDoc in templatesList.docs) {
        final entries = await tmplDoc.reference.collection('entries')
             .where(Filter.or(
                Filter('activity', isEqualTo: oldName),
                Filter('planactivity', isEqualTo: oldName),
             ))
             .get();
        for (final entryDoc in entries.docs) {
           final data = entryDoc.data();
           final updates = <String, dynamic>{};
           if (data['activity'] == oldName) updates['activity'] = newName;
           if (data['planactivity'] == oldName) updates['planactivity'] = newName;
           batch.update(entryDoc.reference, updates);
        }
      }

      await batch.commit();
      await _loadData(); // Reload UI

      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Update successful')));

    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error: $e')));
      // Reload to ensure consistent state
      await _loadData();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showEditDialog(String currentName) {
    final ctrl = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Activity'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Activity Name'),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
             onPressed: () {
               Navigator.pop(ctx);
               final newName = ctrl.text.trim();
               if (newName.isNotEmpty) {
                 _renameOrMerge(currentName, newName);
               }
             },
             child: const Text('Save'),
          ),
        ],
      ),
    );
  }
  
  // Archive/Unarchive logic could be added here too, but prioritized rename/merge first.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Activities')),
      body: _loading 
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _activities.length,
              itemBuilder: (ctx, i) {
                final act = _activities[i];
                return ListTile(
                  title: Text(act),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _showEditDialog(act),
                  ),
                );
              },
            ),
    );
  }
}
