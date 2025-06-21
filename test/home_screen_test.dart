import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/screens/home_screen.dart';

void main() {
  Widget _wrap(Widget child) => MaterialApp(
        home: child,
        routes: {
          '/timeline': (_) => const Scaffold(body: Text('Timeline Page')),
          '/habits': (_) => const Scaffold(body: Text('Habits Page')),
          '/analytics': (_) => const Scaffold(body: Text('Analytics Page')),
        },
      );

  testWidgets('Navigates to timeline when button pressed', (tester) async {
    await tester.pumpWidget(_wrap(const HomeScreen()));

    await tester.tap(find.text("View Today's Timeline"));
    await tester.pumpAndSettle();

    expect(find.text('Timeline Page'), findsOneWidget);
  });

  testWidgets('Navigates to habits when button pressed', (tester) async {
    await tester.pumpWidget(_wrap(const HomeScreen()));

    await tester.tap(find.text('Manage Habits'));
    await tester.pumpAndSettle();

    expect(find.text('Habits Page'), findsOneWidget);
  });

  testWidgets('Navigates to analytics when button pressed', (tester) async {
    await tester.pumpWidget(_wrap(const HomeScreen()));

    await tester.tap(find.text('View Analytics'));
    await tester.pumpAndSettle();

    expect(find.text('Analytics Page'), findsOneWidget);
  });
}