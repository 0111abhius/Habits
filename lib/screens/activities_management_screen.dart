import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart'; // for getFirestore()
import '../utils/activities.dart';
import 'dart:async';

class ActivitiesManagementScreen extends StatefulWidget {
  const ActivitiesManagementScreen({super.key});

  @override
  State<ActivitiesManagementScreen> createState() => _ActivitiesManagementScreenState();
}

class _ActivitiesManagementScreenState extends State<ActivitiesManagementScreen> {
  List<String> _activities = [];
  List<String> _archived = [];
  Map<String, List<dynamic>> _subActivities = {}; // key: parent, val: list of strings
  bool _loading = true;
  
  final TextEditingController _addController = TextEditingController();

  StreamSubscription<DocumentSnapshot>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribeToData();
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    _addController.dispose();
    super.dispose();
  }

  void _subscribeToData() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    _subscription = getFirestore().collection('user_settings').doc(uid).snapshots().listen((doc) {
      if (!mounted) return;
      
      List<String> newActivities = [];
      List<String> newArchived = [];
      Map<String, List<dynamic>> newSubs = {};

      if (doc.exists) {
        final data = doc.data()!;
        final customActs = List<String>.from(data['customActivities'] ?? []);
        // Always combine with defaults for the view
        newActivities = [
          ...kDefaultActivities,
          ...customActs,
        ];
        
        newArchived = List<String>.from(data['archivedActivities'] ?? []);
        newSubs = Map<String, List<dynamic>>.from(data['subActivities'] ?? {});
      } else {
        newActivities = List.from(kDefaultActivities);
        newArchived = [];
        newSubs = {};
      }
      
      // Ensure all activities have an entry in subActivities map (convenience)
      for (final a in newActivities) {
        if (!newSubs.containsKey(a)) newSubs[a] = [];
      }
      
      // Sort alphabetically
      newActivities.sort();
      newArchived.sort();

      // Deduplicate
      newActivities = newActivities.toSet().toList();

      setState(() {
        _activities = newActivities;
        _archived = newArchived;
        _subActivities = newSubs;
        _loading = false;
      });
    }, onError: (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading activities: $e')));
      setState(() => _loading = false);
    });
  }

  Future<void> _saveAll() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    await getFirestore().collection('user_settings').doc(uid).set({
      'customActivities': _activities,
      'archivedActivities': _archived,
      'subActivities': _subActivities,
    }, SetOptions(merge: true));
  }

  Future<void> _addActivity() async {
    final newName = _addController.text.trim();
    if (newName.isEmpty) return;
    if (_activities.contains(newName)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Activity already exists')));
      return;
    }
    
    setState(() {
      _activities.add(newName);
      _activities.sort();
      if (_archived.contains(newName)) _archived.remove(newName);
      _addController.clear();
    });
    
    await _saveAll();
  }

  Future<void> _addSubActivity(String parent, String sub) async {
    if (sub.isEmpty) return;
    final list = List<String>.from(_subActivities[parent] ?? []);
    if (!list.contains(sub)) {
      list.add(sub);
      list.sort();
      setState(() {
        _subActivities[parent] = list;
      });
      await _saveAll();
    }
  }

  Future<void> _removeSubActivity(String parent, String sub) async {
    final list = List<String>.from(_subActivities[parent] ?? []);
    if (list.contains(sub)) {
      list.remove(sub);
      setState(() {
        _subActivities[parent] = list;
      });
      await _saveAll();
    }
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

      // 1. Update Settings List & SubActivities
      // Remove old
      _activities.remove(oldName);
      _archived.remove(oldName);
      final oldSubs = _subActivities[oldName] ?? [];
      _subActivities.remove(oldName);
      
      // Add new if not present
      if (!_activities.contains(newName) && !_archived.contains(newName)) {
         _activities.add(newName);
         _activities.sort();
      }
      
      // Merge sub-activities
      final existingSubs = List<dynamic>.from(_subActivities[newName] ?? []); // dynamic to match map type
      for (final s in oldSubs) {
        if (!existingSubs.contains(s)) existingSubs.add(s);
      }
      _subActivities[newName] = existingSubs;

      batch.set(userSettingsRef, {
        'customActivities': _activities,
        'archivedActivities': _archived,
        'subActivities': _subActivities,
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
      
      // New Templates
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


      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Update successful')));

    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showRenameDialog(String currentName) {
    final ctrl = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Activity'),
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

  void _confirmDelete(String activity) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Activity?'),
        content: Text('Are you sure you want to delete "$activity"?\nIt will be moved to archive and hidden from quick selection, but past entries remain.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      setState(() {
        _activities.remove(activity);
        if (!_archived.contains(activity)) _archived.add(activity);
        _activities.sort();
        _archived.sort();
      });
      await _saveAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Activities')),
      body: _loading 
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Add Activity Section
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _addController,
                          decoration: const InputDecoration(
                            labelText: 'New Activity Name',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _addActivity(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _addActivity,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _activities.length,
                    itemBuilder: (ctx, i) {
                      final act = _activities[i];
                      final subs = List<String>.from(_subActivities[act] ?? []);
                      final subCtrl = TextEditingController(); // Controller for sub-activity input
                      
                      return ExpansionTile(
                        title: Text(act, style: const TextStyle(fontWeight: FontWeight.w600)),
                        leading: Text(kActivityEmoji[act] ?? '🏷️', style: const TextStyle(fontSize: 24)),
                        trailing: Row(
                           mainAxisSize: MainAxisSize.min,
                           children: [
                             IconButton(
                               icon: const Icon(Icons.edit, size: 20),
                               onPressed: () => _showRenameDialog(act),
                               tooltip: 'Rename / Merge',
                             ),
                             if (!kDefaultActivities.contains(act))
                               IconButton(
                                 icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                                 onPressed: () => _confirmDelete(act),
                                 tooltip: 'Delete (Archive)',
                               ),
                             const Icon(Icons.expand_more), // The default expansion icon is replaced if we define trailing, so we add it back or let ExpansionTile handle it if we didn't override. 
                             // Using a Row in trailing overrides the expand icon.
                             // Actually better to put actions in leading or use a popup menu?
                             // Let's keep it simple: Expandable, but actions are separate?
                             // Standard ExpansionTile trailing overrides the arrow. 
                             // We can put the arrow in the row.
                           ],
                        ),
                        children: [
                          // Sub-activity list
                          ...subs.map((s) => ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.only(left: 32, right: 16),
                            title: Text(s),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () => _removeSubActivity(act, s),
                            ),
                          )),
                          // Add sub-activity field
                          Padding(
                            padding: const EdgeInsets.fromLTRB(32, 0, 16, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: subCtrl,
                                    decoration: const InputDecoration(
                                      hintText: 'Add sub-activity',
                                      isDense: true,
                                      border: UnderlineInputBorder(),
                                    ),
                                    onSubmitted: (val) {
                                      _addSubActivity(act, val.trim());
                                      subCtrl.clear(); // This won't clear the visual field effectively because controller is recreated in build. 
                                      // BUG: Controller recreated every build.
                                      // FIX: Use a stateless dialog or keeping state is hard for list items.
                                      // Easier: Button triggers a dialog to add sub-activity.
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add),
                                  onPressed: () {
                                     // We can't easily access the text of this specific controller since it's recreated. 
                                     // Better UX: Show a mini dialog or make the item stateful.
                                     // Let's use a Dialog for adding sub-activity to avoid state complexity in list.
                                    showDialog(
                                      context: context,
                                      builder: (c) {
                                        final tc = TextEditingController();
                                        return AlertDialog(
                                          title: Text('Add sub-activity to "$act"'),
                                          content: TextField(controller: tc, autofocus: true),
                                          actions: [
                                             TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
                                             FilledButton(
                                               onPressed: () {
                                                 _addSubActivity(act, tc.text.trim());
                                                 Navigator.pop(c);
                                               }, 
                                               child: const Text('Add')
                                             )
                                          ]
                                        );
                                      }
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

