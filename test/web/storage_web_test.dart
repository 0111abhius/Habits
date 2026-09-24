@TestOn('browser')
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Firestore web persistence', () {
    setUpAll(() async {
      await Firebase.initializeApp();
    });

    testWidgets('enablePersistence succeeds and data round-trips', (tester) async {
      // enable web IndexedDB persistence (should be noop on VM but succeed in browser)
      await FirebaseFirestore.instance.enablePersistence(const PersistenceSettings(synchronizeTabs: true));

      final coll = FirebaseFirestore.instance.collection('web_test');

      await coll.doc('d').set({'value': 42});
      final snap = await coll.doc('d').get();
      expect(snap.exists, isTrue);
      expect(snap.get('value'), 42);
    });
  });
}