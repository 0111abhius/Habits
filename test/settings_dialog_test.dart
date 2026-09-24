import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:habit_logger/screens/timeline_screen.dart';
import 'helpers.dart';

void main() {
  testWidgets('Add activity appears in dialog and dropdown', (tester) async {
    final fs = await pumpWidgetWithFirestore(tester, const TimelineScreen());

    // open settings
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    // type new activity
    const newCat = 'Dance';
    await tester.enterText(find.byType(TextField).first, newCat);
    // press plus button
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // should see tile in dialog
    expect(find.text(newCat), findsWidgets);

    // close dialog by tapping outside
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // dropdown should now include new activity label
    await tester.tap(find.text('00:00').first);
    await tester.pumpAndSettle();
    expect(find.text(newCat), findsWidgets);

    // firestore should contain in settings
    final docs = await fs.collection('user_settings').get();
    expect(docs.docs.isNotEmpty, true);
    final data = docs.docs.first.data();
    expect((data['customActivities'] as List).contains(newCat), true);
  });
} 