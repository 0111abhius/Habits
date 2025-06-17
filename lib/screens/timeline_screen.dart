import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/timeline_entry.dart';
import '../widgets/calendar_strip.dart';
import '../widgets/habit_tracker.dart';
import '../main.dart';  // Import for getFirestore()
import 'package:intl/intl.dart';
import 'dart:async';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  DateTime selectedDate = DateTime.now();
  static const List<String> _protectedCategories = ['Sleep'];
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
  Map<String, List<String>> _subCategories = {}; // parent -> list of subs

  List<String> _flattenCats() {
    // Use a set to guarantee uniqueness and avoid duplicate Dropdown items
    final flatSet = <String>{};
    for (final parent in _categories) {
      flatSet.add(parent);
      final subs = _subCategories[parent] ?? [];
      for (final s in subs) {
        flatSet.add('$parent / $s');
      }
    }
    return flatSet.toList();
  }

  TimeOfDay? wakeTime;
  TimeOfDay? sleepTime;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _sleepTimeController = TextEditingController();
  final TextEditingController _wakeTimeController = TextEditingController();

  final Map<String, TextEditingController> _noteControllers = {};
  final Map<String, Timer> _noteDebouncers = {};
  double? _pendingScrollOffset;

  Set<int> _splitHours = {}; // hours that have a 30-minute split for the selected date

  bool _dayComplete = false;
  bool _habitsExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadUserSettings();
    _loadDayComplete();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _sleepTimeController.dispose();
    _wakeTimeController.dispose();

    for (final c in _noteControllers.values) {
      c.dispose();
    }
    for (final t in _noteDebouncers.values) {
      t.cancel();
    }
    _noteDebouncers.values.forEach((t) => t.cancel());
    _pendingScrollOffset=null;
    super.dispose();
  }

  // Helper to parse 'HH:mm' strings to TimeOfDay
  TimeOfDay _parseTime(String s) {
    final parts = s.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  Future<void> _reconcileSleepEntriesForSelectedDate() async {
    if (sleepTime == null || wakeTime == null) return;
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final entriesColl = getFirestore()
        .collection('timeline_entries')
        .doc(userId)
        .collection('entries');

    final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
    final snapshot = await entriesColl.where('date', isEqualTo: dateStr).get();
    final entries = snapshot.docs.map((d) => TimelineEntry.fromFirestore(d)).toList();

    for (var hour = 0; hour < 24; hour++) {
      final shouldSleep = _isSleepHour(hour);
      final matching = entries.where((e) => e.startTime.hour == hour);
      final TimelineEntry? existing = matching.isNotEmpty ? matching.first : null;

      final start = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, hour);
      final id = _docId(start);

      if (shouldSleep) {
        // ensure a placeholder exists but DO NOT override if user already set another category
        if (existing == null) {
          final newEntry = TimelineEntry(
            id: id,
            userId: userId,
            date: selectedDate,
            startTime: start,
            endTime: start.add(const Duration(hours: 1)),
            category: 'Sleep',
            notes: '',
          );
          await entriesColl.doc(id).set(newEntry.toMap(), SetOptions(merge: true));
        } else if (existing.category.isEmpty) {
          // only auto-fill if user hasn't picked something yet
          await entriesColl.doc(existing.id).update({'category': 'Sleep'});
        }
      } else {
        // should NOT be sleep
        if (existing != null && existing.category == 'Sleep') {
          await entriesColl.doc(existing.id).update({'category': ''});
        }
      }
    }
  }

  Future<void> _loadUserSettings() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final settingsRef = getFirestore()
          .collection('user_settings')
          .doc(user.uid);

      final settings = await settingsRef.get();
      if (settings.exists) {
        final data = settings.data()!;
        final sleepTxt = data['sleepTime'] ?? '23:00';
        final wakeTxt = data['wakeTime'] ?? '7:00';

        setState(() {
          _sleepTimeController.text = sleepTxt;
          _wakeTimeController.text = wakeTxt;
          sleepTime = _parseTime(sleepTxt);
          wakeTime = _parseTime(wakeTxt);
          _categories = List<String>.from(data['customCategories'] ?? []);
          _subCategories = (data['subCategories'] as Map<String, dynamic>? ?? {})
              .map((k, v) => MapEntry(k, List<String>.from(v as List)));
          _dedupCats();
          // ensure 'Sleep' is always present
          if (!_categories.contains('Sleep')) {
            _categories.insert(0,'Sleep');
          }
        });

        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToWakeTime());
        await _reconcileSleepEntriesForSelectedDate();
      } else {
        // Initialize with default settings if none exist
        await settingsRef.set({
          'sleepTime': '23:00',
          'wakeTime': '7:00',
          'customCategories': ['Work', 'Personal', 'Health', 'Other'],
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        setState(() {
          _sleepTimeController.text = '23:00';
          _wakeTimeController.text = '7:00';
          _categories = List.from(_initialCategories);
          _dedupCats();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToWakeTime());
        await _reconcileSleepEntriesForSelectedDate();
      }
    } catch (e) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        const SnackBar(content: Text('Unable to load settings. Please try again later.')),
      );
    }
  }

  void _scrollToWakeTime() {
    if (wakeTime == null) return;
    const itemHeight = 120.0;
    final offset = wakeTime!.hour * itemHeight;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(offset.clamp(0, _scrollController.position.maxScrollExtent));
    } else {
      _pendingScrollOffset = offset;
    }
  }

  bool _isSleepHour(int hour) {
    if (sleepTime == null || wakeTime == null) return false;
    final sleepHour = sleepTime!.hour;
    final wakeHour = wakeTime!.hour;
    if (sleepHour < wakeHour) {
      return hour >= sleepHour && hour < wakeHour;
    } else {
      // Sleep crosses midnight
      return hour >= sleepHour || hour < wakeHour;
    }
  }

  String _docId(DateTime dt) => DateFormat('yyyyMMdd_HHmm').format(dt);

  Future<void> _ensureSleepEntry(int hour, List<TimelineEntry> existingEntries) async {
    final alreadyExists = existingEntries.any((e) => e.startTime.hour == hour);
    if (alreadyExists) return;
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    final start = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, hour);
    final newEntry = TimelineEntry(
      id: _docId(start),
      userId: userId,
      date: selectedDate,
      startTime: start,
      endTime: start.add(const Duration(hours: 1)),
      category: 'Sleep',
      notes: '',
    );
    final entriesColl = getFirestore()
        .collection('timeline_entries')
        .doc(userId)
        .collection('entries');
    await entriesColl.doc(newEntry.id).set(newEntry.toMap(), SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timeline'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Analytics',
            onPressed: () => Navigator.pushNamed(context, '/analytics'),
          ),
          PopupMenuButton<String>(
            tooltip: 'Customize',
            onSelected: (value) async {
              switch (value) {
                case 'sleep':
                  _showSleepDialog(context);
                  break;
                case 'categories':
                  _showCategoriesDialog(context);
                  break;
                case 'habits':
                  Navigator.pushNamed(context, '/habits');
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'sleep',
                child: ListTile(
                  leading: const Icon(Icons.bedtime),
                  title: const Text('Sleep timings'),
                ),
              ),
              PopupMenuItem(
                value: 'categories',
                child: ListTile(
                  leading: const Icon(Icons.label),
                  title: const Text('Categories'),
                ),
              ),
              PopupMenuItem(
                value: 'habits',
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Habits'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          CalendarStrip(
            selectedDate: selectedDate,
            onDateSelected: (date) {
              setState(() {
                // clear controllers when switching date to avoid residue
                for (final c in _noteControllers.values) {
                  c.dispose();
                }
                _noteControllers.clear();
                _noteDebouncers.clear();

                selectedDate = date;
                _loadDayComplete();
                _scrollToWakeTime();
              });
            },
          ),
          CheckboxListTile(
            title: const Text('Day fully logged'),
            value: _dayComplete,
            onChanged: (val){if(val!=null) _setDayComplete(val);},
          ),
          ExpansionTile(
            title: const Text('Habits'),
            initiallyExpanded: _habitsExpanded,
            maintainState: true,
            onExpansionChanged: (expanded) {
              setState(() => _habitsExpanded = expanded);
            },
            children: [
              HabitTracker(date: selectedDate),
            ],
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: getFirestore()
                  .collection('timeline_entries')
                  .doc(FirebaseAuth.instance.currentUser?.uid ?? '')
                  .collection('entries')
                  .where('date', isEqualTo: DateFormat('yyyy-MM-dd').format(selectedDate))
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                var entries = snapshot.data?.docs
                        .map((doc) => TimelineEntry.fromFirestore(doc))
                        .toList() ?? [];

                // update splitHours set based on presence of :30 entries
                _splitHours = entries
                    .where((e) => e.startTime.minute == 30)
                    .map((e) => e.startTime.hour)
                    .toSet();

                // Autofill sleep blocks
                if (sleepTime != null && wakeTime != null) {
                  for (var hour = 0; hour < 24; hour++) {
                    if (_isSleepHour(hour)) {
                      _ensureSleepEntry(hour, entries);
                    }
                  }
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_pendingScrollOffset!=null && _scrollController.hasClients) {
                    final max=_scrollController.position.maxScrollExtent;
                    _scrollController.jumpTo(_pendingScrollOffset!.clamp(0,max));
                    _pendingScrollOffset=null;
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  itemCount: 24,
                  itemBuilder: (context, hour) {
                    // Retrieve any existing entries for this hour and minute markers
                    TimelineEntry _blank(int minute) {
                      final start=DateTime(selectedDate.year,selectedDate.month,selectedDate.day,hour,minute);
                      return TimelineEntry(
                        id: _docId(start),
                        userId: FirebaseAuth.instance.currentUser?.uid ?? '',
                        date: selectedDate,
                        startTime: DateTime(selectedDate.year, selectedDate.month, selectedDate.day, hour, minute),
                        endTime: DateTime(selectedDate.year, selectedDate.month, selectedDate.day, hour, minute).add(Duration(minutes: minute==0?60:30)),
                        category: '',
                        notes: '',
                      );
                    }

                    final entry00 = entries.firstWhere(
                      (e) => e.startTime.hour == hour && e.startTime.minute == 0,
                      orElse: () => _blank(0),
                    );

                    final entry30 = _splitHours.contains(hour)
                        ? entries.firstWhere(
                            (e) => e.startTime.hour == hour && e.startTime.minute == 30,
                            orElse: () => _blank(30),
                          )
                        : null;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Column(
                        children: [
                          ListTile(
                            title: Text('${hour.toString().padLeft(2, '0')}:00'),
                            trailing: IconButton(
                              icon: Icon(_splitHours.contains(hour) ? Icons.call_merge : Icons.call_split),
                              onPressed: () => _toggleSplit(hour),
                            ),
                          ),
                          _buildSubBlock(entry00, hour, 0),
                          if (entry30 != null) _buildSubBlock(entry30, hour, 30),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateEntry(TimelineEntry entry, String category, String notes) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final entriesColl = getFirestore()
          .collection('timeline_entries')
          .doc(user.uid)
          .collection('entries');

      final updatedEntry = TimelineEntry(
        id: '',
        userId: user.uid,
        date: entry.date,
        startTime: entry.startTime,
        endTime: entry.endTime,
        category: category,
        notes: notes,
      );

      final docId = _docId(updatedEntry.startTime);
      await entriesColl.doc(docId).set(updatedEntry.toMap(), SetOptions(merge: true));
    } catch (e) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        const SnackBar(content: Text('Unable to update entry. Please try again later.')),
      );
    }
  }

  Future<void> _showSleepDialog(BuildContext context) async {
    TimeOfDay? dialogSleep = sleepTime ?? (_sleepTimeController.text.isNotEmpty ? _parseTime(_sleepTimeController.text) : const TimeOfDay(hour: 23, minute: 0));
    TimeOfDay? dialogWake = wakeTime ?? (_wakeTimeController.text.isNotEmpty ? _parseTime(_wakeTimeController.text) : const TimeOfDay(hour: 7, minute: 0));

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Sleep Timings'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Sleep Time'),
                      TextButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: dialogSleep ?? const TimeOfDay(hour: 23, minute: 0),
                          );
                          if (t != null) {
                            setDialogState(() => dialogSleep = t);
                            _sleepTimeController.text = _fmt24(t);
                            await _saveSettings();
                          }
                        },
                        child: Text(dialogSleep?.format(context) ?? 'Set'),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Wake Time'),
                      TextButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: dialogWake ?? const TimeOfDay(hour: 7, minute: 0),
                          );
                          if (t != null) {
                            setDialogState(() => dialogWake = t);
                            _wakeTimeController.text = _fmt24(t);
                            await _saveSettings();
                          }
                        },
                        child: Text(dialogWake?.format(context) ?? 'Set'),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCategoriesDialog(BuildContext context) async {
    final TextEditingController addCatController = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Categories', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: addCatController,
                              decoration: const InputDecoration(labelText: 'Add category'),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () async {
                              final newCat = addCatController.text.trim();
                              if (newCat.isEmpty) return;
                              setDialogState(() {
                                _categories.add(newCat);
                                _dedupCats();
                              });
                              addCatController.clear();
                              await _saveSettings();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 300),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _categories.length,
                          itemBuilder: (context, index) {
                            final parent = _categories[index];
                            final subs = _subCategories[parent] ?? [];
                            final isDefault = _protectedCategories.contains(parent);
                            final TextEditingController subCtrl = TextEditingController();
                            return ExpansionTile(
                              title: Text(parent),
                              trailing: isDefault
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.delete),
                                      onPressed: () async {
                                        setDialogState(() {
                                          _categories.remove(parent);
                                          _subCategories.remove(parent);
                                          _dedupCats();
                                        });
                                        await _saveSettings();
                                      },
                                    ),
                              children: [
                                ...subs.map((s) => Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(s),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline),
                                            onPressed: () async {
                                              await _removeSubCategory(parent, s);
                                              setDialogState(() {});
                                            },
                                          ),
                                        ],
                                      ),
                                    )),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: subCtrl,
                                          decoration: const InputDecoration(labelText: 'Add sub-category'),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline),
                                        onPressed: () async {
                                          final sub = subCtrl.text.trim();
                                          if (sub.isEmpty) return;
                                          await _addSubCategory(parent, sub);
                                          subCtrl.clear();
                                          setDialogState(() {});
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
                      const SizedBox(height: 8),
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveSettings() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final settingsRef = getFirestore()
          .collection('user_settings')
          .doc(user.uid);

      _dedupCats();

      // Determine if times actually changed (compare by hour/minute not string)
      TimeOfDay _toTod(String s) => _parseTime(s);

      final prevSleep = sleepTime ?? _toTod(_sleepTimeController.text);
      final prevWake = wakeTime ?? _toTod(_wakeTimeController.text);
      final newSleep = _toTod(_sleepTimeController.text);
      final newWake = _toTod(_wakeTimeController.text);
      final bool timesChanged = prevSleep != newSleep || prevWake != newWake;

      await settingsRef.set({
        'sleepTime': _sleepTimeController.text,
        'wakeTime': _wakeTimeController.text,
        'customCategories': _categories,
        'subCategories': _subCategories,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // refresh local vars
      if (mounted) {
        setState(() {
          if (timesChanged) {
            sleepTime = newSleep;
            wakeTime = newWake;
          }
          // ensure categories list refreshes in timeline & dropdown
          _categories = List<String>.from(_categories);
        });

        if (timesChanged) {
          // after rebuild, scroll
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToWakeTime());
        }
      }

      if (timesChanged) {
        // reconcile entries for selected date so timeline reflects new range instantly
        await _reconcileSleepEntriesForSelectedDate();
      }

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    } catch (e) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Unable to save settings. Please try again later.')),
      );
    }
  }

  String _fmt24(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _dedupCats() {
    _categories = _categories.toSet().toList();
  }

  Future<void> _toggleSplit(int hour) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    // remember scroll offset to avoid jump
    final double prevOffset = _scrollController.hasClients ? _scrollController.offset : 0;
    final entriesColl = getFirestore()
        .collection('timeline_entries')
        .doc(userId)
        .collection('entries');

    final halfStart = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, hour, 30);
    final halfDocId = _docId(halfStart);

    if (_splitHours.contains(hour)) {
      // merge: remove :30 entry
      await entriesColl.doc(halfDocId).delete();
      _splitHours.remove(hour);
      final k = _noteKey(hour, 30);
      _noteControllers[k]?.dispose();
      _noteControllers.remove(k);
      _noteDebouncers[k]?.cancel();
      _noteDebouncers.remove(k);
    } else {
      // split: create empty :30 entry if not exists
      final newEntry = TimelineEntry(
        id: halfDocId,
        userId: userId,
        date: selectedDate,
        startTime: halfStart,
        endTime: halfStart.add(const Duration(minutes: 30)),
        category: '',
        notes: '',
      );
      await entriesColl.doc(halfDocId).set(newEntry.toMap());
      _splitHours.add(hour);
    }
    if (mounted) setState(() {});

    _pendingScrollOffset = prevOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pendingScrollOffset!=null && _scrollController.hasClients) {
        final max=_scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(_pendingScrollOffset!.clamp(0,max));
        _pendingScrollOffset=null;
      }
    });
  }

  String _noteKey(int hour, int minute) => '${hour.toString().padLeft(2,'0')}:${minute.toString().padLeft(2,'0')}';

  Widget _buildSubBlock(TimelineEntry entry, int hour, int minute) {
    final key = _noteKey(hour, minute);
    final controller = _noteControllers.putIfAbsent(key, () => TextEditingController(text: entry.notes));
    // keep controller text in sync if backend changed (but avoid disrupting typing)
    if (controller.text != entry.notes && !_noteDebouncers.containsKey(key)) {
      controller.text = entry.notes;
      controller.selection = TextSelection.collapsed(offset: controller.text.length);
    }

    // Pre-compute flattened categories once to avoid redundant work and help with value validation
    final availableCategories = _flattenCats();
    // If the entry.category is no longer present in the available list (e.g. the sub-category was deleted),
    // fall back to null so that DropdownButton does not throw an assertion.
    final String? dropdownValue =
        (entry.category.isNotEmpty && availableCategories.contains(entry.category))
            ? entry.category
            : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButton<String>(
            value: dropdownValue,
            hint: const Text('Select category'),
            items: availableCategories
                .map((category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    ))
                .toList(),
            onChanged: (val) {
              if (val != null) _updateEntry(entry, val, entry.notes);
            },
          ),
          TextField(
            controller: controller,
            maxLines: null,
            decoration: const InputDecoration(hintText: 'Add notes...', border: InputBorder.none),
            onChanged: (val) {
              _noteDebouncers[key]?.cancel();
              _noteDebouncers[key] = Timer(const Duration(milliseconds: 500), () {
                _updateEntry(entry, entry.category, val);
                _noteDebouncers.remove(key);
              });
            },
          ),
        ],
      ),
    );
  }

  String _dateStr(DateTime d)=>DateFormat('yyyy-MM-dd').format(d);

  Future<void> _loadDayComplete() async{
    final uid=FirebaseAuth.instance.currentUser?.uid; if(uid==null) return;
    final doc=await getFirestore().collection('daily_logs').doc(uid).collection('logs').doc(_dateStr(selectedDate)).get();
    setState(()=>_dayComplete=doc.exists && (doc.data()?['complete']==true));
  }

  Future<void> _setDayComplete(bool val) async{
    final uid=FirebaseAuth.instance.currentUser?.uid; if(uid==null) return;
    final ref=getFirestore().collection('daily_logs').doc(uid).collection('logs').doc(_dateStr(selectedDate));
    if(val){
      await ref.set({'date':_dateStr(selectedDate),'lastUpdated':FieldValue.serverTimestamp()});
    }else{
      await ref.delete();
    }
    setState(()=>_dayComplete=val);
  }

  // ---------- Sub-category helpers ----------
  Future<void> _addSubCategory(String parent, String sub) async {
    if (sub.trim().isEmpty) return;
    if (!_categories.contains(parent)) {
      _categories.add(parent);
    }
    final list = _subCategories[parent] ?? <String>[];
    if (!list.contains(sub)) {
      list.add(sub);
      _subCategories[parent] = list;
      await _saveSettings();
      if (mounted) setState(() {});
    }
  }

  Future<void> _removeSubCategory(String parent, String sub) async {
    final list = _subCategories[parent];
    if (list == null) return;
    list.remove(sub);
    if (list.isEmpty) {
      _subCategories.remove(parent);
    } else {
      _subCategories[parent] = list;
    }
    await _saveSettings();
    if (mounted) setState(() {});
  }
} 