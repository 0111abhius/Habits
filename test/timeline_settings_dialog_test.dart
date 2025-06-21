import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:habit_logger/main.dart';
import 'package:habit_logger/screens/timeline_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // no-op shims defined in test/helpers.dart but import again for compile.
  import 'helpers.dart' as _;

  group('Timeline settings dialogs', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;

    setUp(() async {
      await Firebase.initializeApp();
      firestore = FakeFirebaseFirestore();
      overrideFirestoreForTests(firestore);

      final user = MockUser(uid: 'uid1', email: 't@e.com');
      auth = MockFirebaseAuth(mockUser: user);
      await auth.signInWithCustomToken('token');
    });

    testWidgets('Adding custom activity persists to Firestore', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TimelineScreen()));
      await tester.pumpAndSettle();

      // open customize menu
      await tester.tap(find.byTooltip('Customize'));
      await tester.pumpAndSettle();

      // select Activities
      await tester.tap(find.text('Activities'));
      await tester.pumpAndSettle();

      // enter new activity text and tap add icon
      const newAct = 'Chess';
      await tester.enterText(find.byType(TextField).first, newAct);
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      // verify it appears in dialog list
      expect(find.text(newAct), findsWidgets);

      // close dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Firestore should contain customActivities field
      final snap = await firestore.collection('user_settings').doc('uid1').get();
      final list = List<String>.from(snap.data()?['customActivities'] ?? []);
      expect(list.contains(newAct), isTrue);
    });
  });
}