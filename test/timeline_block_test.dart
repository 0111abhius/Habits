import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/screens/timeline_screen.dart';
import 'helpers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

void main() {
  testWidgets('Selecting category writes deterministic doc', (tester) async {
    final fs = await pumpWidgetWithFirestore(tester, const TimelineScreen());

    // tap first dropdown (00:00)
    await tester.tap(find.text('00:00').first);
    await tester.pumpAndSettle();

    // choose 'Work'
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();

    final today = DateTime.now();
    final id = DateFormat('yyyyMMdd_00').format(today);
    final doc = await fs
        .collection('timeline_entries')
        .doc('') // any user id is empty in tests
        .collection('entries')
        .doc(id)
        .get();
    expect(doc.exists, true);
    expect(doc.data()!['category'], 'Work');
  });
} 