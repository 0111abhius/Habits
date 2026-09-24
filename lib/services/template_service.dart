import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/template.dart';
import '../models/timeline_entry.dart';

/// Day templates: `user_templates/{uid}/templates/{id}` with an `entries`
/// subcollection keyed by `HHmm` (`:00` entries are 60 minutes unless a `:30`
/// entry exists for that hour).
class TemplateService {
  final FirebaseFirestore _db;
  TemplateService({FirebaseFirestore? firestore}) : _db = firestore ?? getFirestore();

  CollectionReference<Map<String, dynamic>> _templates(String uid) =>
      _db.collection('user_templates').doc(uid).collection('templates');

  CollectionReference<Map<String, dynamic>> _entries(String uid, String templateId) =>
      _templates(uid).doc(templateId).collection('entries');

  CollectionReference<Map<String, dynamic>> _timeline(String uid) =>
      _db.collection('timeline_entries').doc(uid).collection('entries');

  DocumentReference<Map<String, dynamic>> _dailyLog(String uid, DateTime date) =>
      _db.collection('daily_logs').doc(uid).collection('logs').doc(dateKey(date));

  static String dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  static String entryId(DateTime dt) => DateFormat('yyyyMMdd_HHmm').format(dt);

  Future<List<Template>> fetchTemplates(String uid) async {
    final snap = await _templates(uid).get();
    final list = snap.docs.map((d) => Template.fromFirestore(d)).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// The template that auto-applies on [date]'s weekday (first match), or
  /// null. Expired templates (`validUntil` in the past) are skipped.
  Future<Template?> templateForDate(String uid, DateTime date) async {
    final snap = await _templates(uid).where('daysOfWeek', arrayContains: date.weekday).get();
    for (final doc in snap.docs) {
      final data = doc.data();
      final vu = data['validUntil'];
      if (vu is Timestamp) {
        final v = vu.toDate();
        if (DateTime(date.year, date.month, date.day).isAfter(DateTime(v.year, v.month, v.day))) continue;
      }
      return Template.fromFirestore(doc);
    }
    return null;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _templateEntries(String uid, String templateId) async =>
      (await _entries(uid, templateId).get()).docs;

  /// Fills [date]'s plan from [templateId] (or the weekday's template when
  /// null). Existing planned hours are kept unless [overwrite] is set; locked
  /// / workBlock flags from the template are propagated. Returns the number
  /// of slots written. Marks the day as `templateApplied` so the timeline
  /// does not re-apply on refresh.
  Future<int> applyToDate(
    String uid,
    DateTime date, {
    String? templateId,
    bool overwrite = false,
  }) async {
    String? id = templateId;
    if (id == null) {
      final t = await templateForDate(uid, date);
      if (t == null) return 0;
      id = t.id;
    }
    final tmplDocs = await _templateEntries(uid, id);
    if (tmplDocs.isEmpty) return 0;

    final existingSnap = await _timeline(uid).where('date', isEqualTo: dateKey(date)).get();
    final existing = <String, TimelineEntry>{
      for (final d in existingSnap.docs)
        _hm(TimelineEntry.fromMap(d.id, d.data()).startTime): TimelineEntry.fromMap(d.id, d.data()),
    };

    final batch = _db.batch();
    int written = 0;
    for (final doc in tmplDocs) {
      final hour = int.parse(doc.id.substring(0, 2));
      final minute = int.parse(doc.id.substring(2));
      final data = doc.data();
      final planCat = (data['planactivity'] ?? data['activity'] ?? '') as String;
      final planNotes = (data['planNotes'] ?? data['notes'] ?? '') as String;
      final retroCat = (data['activity'] ?? '') == 'Sleep' ? 'Sleep' : '';
      final locked = data['locked'] == true;
      final workBlock = data['workBlock'] == true;
      final key = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

      final cur = existing[key];
      if (cur != null) {
        final upd = <String, dynamic>{};
        // Overwriting keeps slots that hold a placed task.
        final canWritePlan = cur.planactivity.isEmpty || (overwrite && cur.taskId == null);
        if (canWritePlan) {
          upd['planactivity'] = planCat;
          upd['planNotes'] = planNotes;
        }
        if (retroCat.isNotEmpty && cur.activity.isEmpty) {
          upd['activity'] = retroCat;
        }
        if (locked != cur.locked) upd['locked'] = locked;
        if (workBlock != cur.workBlock) upd['workBlock'] = workBlock;
        if (upd.isNotEmpty) {
          batch.set(_timeline(uid).doc(cur.id), upd, SetOptions(merge: true));
          written++;
        }
        continue;
      }

      final start = DateTime(date.year, date.month, date.day, hour, minute);
      final entry = TimelineEntry(
        id: entryId(start),
        userId: uid,
        date: DateTime(date.year, date.month, date.day),
        startTime: start,
        endTime: start.add(Duration(minutes: minute == 0 ? 60 : 30)),
        planactivity: planCat,
        planNotes: planNotes,
        activity: retroCat,
        notes: '',
        locked: locked,
        workBlock: workBlock,
      );
      batch.set(_timeline(uid).doc(entry.id), entry.toMap());
      written++;
    }
    batch.set(_dailyLog(uid, date), {'templateApplied': true, 'templateId': id}, SetOptions(merge: true));
    await batch.commit();
    return written;
  }

  /// Clears the planned column for [date] (except Sleep and locked slots
  /// when [keepLocked]), so another template can be applied cleanly.
  Future<void> clearPlan(String uid, DateTime date, {bool keepLocked = false}) async {
    final snap = await _timeline(uid).where('date', isEqualTo: dateKey(date)).get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      final e = TimelineEntry.fromMap(d.id, d.data());
      if (e.planactivity == 'Sleep') continue;
      if (keepLocked && e.locked) continue;
      batch.set(
        d.reference,
        {
          'planactivity': '',
          'planNotes': '',
          'locked': false,
          'workBlock': false,
          'taskId': FieldValue.delete(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  /// Creates or replaces a template's metadata and entries.
  Future<String> upsertTemplate(
    String uid, {
    String? templateId,
    required String name,
    required List<int> daysOfWeek,
    required Map<String, Map<String, dynamic>> entries,
  }) async {
    final ref = templateId != null ? _templates(uid).doc(templateId) : _templates(uid).doc();
    final batch = _db.batch();
    batch.set(ref, {'name': name, 'daysOfWeek': daysOfWeek, 'isDefault': false}, SetOptions(merge: true));
    if (templateId != null) {
      final old = await ref.collection('entries').get();
      for (final d in old.docs) {
        batch.delete(d.reference);
      }
    }
    entries.forEach((id, data) => batch.set(ref.collection('entries').doc(id), data));
    await batch.commit();
    return ref.id;
  }

  /// Removes [days] from every template other than [exceptId] so a weekday
  /// auto-applies at most one template. Returns the names of templates that
  /// were changed.
  Future<List<String>> releaseDays(String uid, List<int> days, {String? exceptId}) async {
    if (days.isEmpty) return const [];
    final snap = await _templates(uid).get();
    final batch = _db.batch();
    final changed = <String>[];
    for (final d in snap.docs) {
      if (d.id == exceptId) continue;
      final current = List<int>.from(d.data()['daysOfWeek'] ?? const []);
      final next = current.where((x) => !days.contains(x)).toList();
      if (next.length != current.length) {
        batch.set(d.reference, {'daysOfWeek': next}, SetOptions(merge: true));
        changed.add(d.data()['name'] as String? ?? d.id);
      }
    }
    if (changed.isNotEmpty) await batch.commit();
    return changed;
  }

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
