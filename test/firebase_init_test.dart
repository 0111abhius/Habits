import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/main.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  test('getFirestore returns same instance and custom dbId', () async {
    await Firebase.initializeApp();

    final first = getFirestore();
    final second = getFirestore();

    expect(identical(first, second), isTrue);
    expect(first.app.name, Firebase.app().name);
  });

  test('overrideFirestoreForTests injects fake instance', () async {
    final fake = FakeFirebaseFirestore();
    overrideFirestoreForTests(fake);
    expect(getFirestore(), fake);
  });
}