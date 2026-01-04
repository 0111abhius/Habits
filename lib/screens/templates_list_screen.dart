import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import '../models/template.dart';
import 'template_screen.dart';

class TemplatesListScreen extends StatefulWidget {
  const TemplatesListScreen({Key? key}) : super(key: key);

  @override
  State<TemplatesListScreen> createState() => _TemplatesListScreenState();
}

class _TemplatesListScreenState extends State<TemplatesListScreen> {
  List<Template> _templates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Check migration
    await _checkMigration(uid);

    final snapshot = await getFirestore()
        .collection('user_templates')
        .doc(uid)
        .collection('templates')
        .get();

    setState(() {
      _templates = snapshot.docs.map((d) => Template.fromFirestore(d)).toList();
      _loading = false;
    });
  }

  Future<void> _checkMigration(String uid) async {
    final templatesRef = getFirestore().collection('user_templates').doc(uid).collection('templates');
    final tmplSnap = await templatesRef.limit(1).get();
    if (tmplSnap.docs.isNotEmpty) return; // Already have templates

    // Check legacy
    final legacyRef = getFirestore().collection('template_entries').doc(uid).collection('entries');
    final legacySnap = await legacyRef.get();
    if (legacySnap.docs.isEmpty) return; // Nothing to migrate area

    // Migrate
    final newDoc = templatesRef.doc();
    await newDoc.set({
      'name': 'Default',
      'daysOfWeek': [1, 2, 3, 4, 5, 6, 7],
      'isDefault': true,
    });

    final batch = getFirestore().batch();
    for (final doc in legacySnap.docs) {
      batch.set(newDoc.collection('entries').doc(doc.id), doc.data());
    }
    await batch.commit();
  }

  Future<void> _addTemplate() async {
    final TextEditingController nameCtrl = TextEditingController();
    final List<int> selectedDays = [];
    
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New Template'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Template Name'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              const Text('Applies to:'),
              Wrap(
                spacing: 8,
                children: List.generate(7, (index) {
                  final day = index + 1;
                  final isSelected = selectedDays.contains(day);
                  return FilterChip(
                    label: Text(_dayName(day)),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          selectedDays.add(day);
                        } else {
                          selectedDays.remove(day);
                        }
                      });
                    },
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid != null) {
                  await getFirestore()
                      .collection('user_templates')
                      .doc(uid)
                      .collection('templates')
                      .add({
                    'name': nameCtrl.text.trim(),
                    'daysOfWeek': selectedDays,
                    'isDefault': false,
                  });
                  _loadTemplates();
                }
                Navigator.pop(ctx);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  String _dayName(int d) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[d - 1];
  }

  Future<void> _editTemplateMetadata(Template t) async {
    final TextEditingController nameCtrl = TextEditingController(text: t.name);
    final List<int> selectedDays = List.from(t.daysOfWeek);
    
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Template'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Template Name'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              const Text('Applies to:'),
              Wrap(
                spacing: 8,
                children: List.generate(7, (index) {
                  final day = index + 1;
                  final isSelected = selectedDays.contains(day);
                  return FilterChip(
                    label: Text(_dayName(day)),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          selectedDays.add(day);
                        } else {
                          selectedDays.remove(day);
                        }
                      });
                    },
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            if(!t.isDefault)
              TextButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Delete Template?'),
                      content: const Text('This cannot be undone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    if (uid != null) {
                      await getFirestore().collection('user_templates').doc(uid).collection('templates').doc(t.id).delete();
                      _loadTemplates();
                    }
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid != null) {
                  await getFirestore()
                      .collection('user_templates')
                      .doc(uid)
                      .collection('templates')
                      .doc(t.id)
                      .update({
                    'name': nameCtrl.text.trim(),
                    'daysOfWeek': selectedDays,
                  });
                  _loadTemplates();
                }
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _templates.length,
              itemBuilder: (ctx, i) {
                final t = _templates[i];
                final days = t.daysOfWeek.map(_dayName).join(', ');
                return ListTile(
                  title: Text(t.name),
                  subtitle: Text(days.isEmpty ? 'No days selected' : days),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TemplateScreen(templateId: t.id, templateName: t.name)),
                    );
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () => _editTemplateMetadata(t),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTemplate,
        child: const Icon(Icons.add),
      ),
    );
  }
}
