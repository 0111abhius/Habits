import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/widgets/calendar_strip.dart';

void main() {
  testWidgets('Selecting a date triggers callback', (tester) async {
    late DateTime picked;
    final today = DateTime.now();

    await tester.pumpWidget(
      MaterialApp(
        home: CalendarStrip(
          selectedDate: today,
          onDateSelected: (d) => picked = d,
        ),
      ),
    );

    // Tap the first rendered date tile (index 0)
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
  });
}