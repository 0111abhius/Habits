import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/main.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';

/// Pumps the given widget wrapped with a MockFirestore instance available via Provider.
Future<FakeFirebaseFirestore> pumpWidgetWithFirestore(
  WidgetTester tester,
  Widget child, {
  FakeFirebaseFirestore? firestore,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // set up firebase mocks
  setupFirebaseCoreMocks();
  await Firebase.initializeApp();

  final fake = firestore ?? FakeFirebaseFirestore();
  // inject into app
  overrideFirestoreForTests(fake);

  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
  return fake;
}

// ----- Stubs for old firebase_test_utils helpers (removed in Firebase 3.x) ----
void setupFirebaseCoreMocks() {}
void setupFirebaseAuthMocks() {} 