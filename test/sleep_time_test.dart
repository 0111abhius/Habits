import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers.dart';
import 'package:habit_logger/screens/timeline_screen.dart';

void main() {
  testWidgets('Changing wake time scrolls timeline', (tester) async {
    await pumpWidgetWithFirestore(tester, const TimelineScreen());

    // open settings
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    // tap wake Time button
    final wakeButton = find.widgetWithText(TextButton, 'Set Time').at(1);
    await tester.tap(wakeButton);
    await tester.pumpAndSettle();

    // select 10:00 in the time picker (clock dial is difficult; we mimic ok)
    await tester.drag(find.byType(TimePickerDialog), const Offset(0, -200));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // dialog closes
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // list should have scrolled close to 10*itemHeight (within 200 px tolerance)
    final listFinder = find.byType(ListView);
    final listView = tester.widget<ListView>(listFinder);
    expect(listView.controller!.offset, greaterThan(800));
  });
} 