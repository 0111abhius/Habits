import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:habit_logger/main.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App launches and shows login screen', (tester) async {
    // setup firebase mocks (core only). Auth etc handled separately.
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Login screen should display welcome text
    expect(find.text('Welcome'), findsOneWidget);
  });
}