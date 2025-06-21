import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/models/timeline_entry.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  group('TimelineEntry model', () {
    test('toMap creates expected structure', () {
      final entry = TimelineEntry(
        id: 'e1',
        userId: 'user123',
        date: DateTime(2024, 01, 15),
        startTime: DateTime(2024, 01, 15, 8, 0),
        endTime: DateTime(2024, 01, 15, 9, 0),
        activity: 'Study',
        notes: 'Math chapter',
      );

      final map = entry.toMap();

      expect(map['userId'], 'user123');
      expect(map['date'], '2024-01-15');
      expect(map['hour'], 8);
      expect(map['activity'], 'Study');
      expect(map['notes'], 'Math chapter');
      expect(map['startTime'], isA<Timestamp>());
      expect(map['endTime'], isA<Timestamp>());
    });

    test('fromFirestore reconstructs same data', () async {
      final firestore = FakeFirebaseFirestore();
      final original = TimelineEntry(
        id: 'ignored',
        userId: 'userABC',
        date: DateTime(2024, 02, 01),
        startTime: DateTime(2024, 02, 01, 6),
        endTime: DateTime(2024, 02, 01, 7),
        planactivity: 'Run',
        planNotes: 'Morning run',
        activity: 'Run',
        notes: '5km',
      );

      // Save to fake firestore and read back
      final docRef = await firestore.collection('entries').add(original.toMap());
      final snap = await docRef.get();
      final reconstructed = TimelineEntry.fromFirestore(snap);

      expect(reconstructed.id, docRef.id);
      expect(reconstructed.userId, original.userId);
      expect(reconstructed.date, original.date);
      expect(reconstructed.startTime, original.startTime);
      expect(reconstructed.endTime, original.endTime);
      expect(reconstructed.activity, original.activity);
      expect(reconstructed.notes, original.notes);
      expect(reconstructed.planactivity, original.planactivity);
      expect(reconstructed.planNotes, original.planNotes);
    });
  });
}