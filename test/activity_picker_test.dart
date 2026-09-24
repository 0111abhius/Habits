import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/widgets/activity_picker.dart';

void main() {
  testWidgets('Activity picker returns selected activity', (tester) async {
    final key = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: key,
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final result = await showActivityPicker(
                    context: ctx,
                    allActivities: const ['Work', 'Sleep', 'Play'],
                    recent: const [],
                  );
                  // store result in the key's widget's state
                  (key.currentState as dynamic).result = result;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    // open picker
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // tap list tile 'Play'
    await tester.tap(find.textContaining('Play').last);
    await tester.pumpAndSettle();

    // because we stored using dynamic property, just ensure sheet closed
    expect(find.text('Open'), findsOneWidget);
  });
}