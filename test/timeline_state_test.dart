import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/main.dart';
import 'package:habit_logger/screens/timeline_screen.dart';
import 'package:intl/intl.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:habit_logger/widgets/habit_tracker.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  // Common boot-strap for each test.
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    setupFirebaseAuthMocks();
    await Firebase.initializeApp();

    // Fake Firestore for each test
    firestore = FakeFirebaseFirestore();
    overrideFirestoreForTests(firestore);

    // Ensure a signed-in user so Timeline features work.
    final mockUser = MockUser(uid: 'test_uid', email: 'a@b.com');
    final auth = MockFirebaseAuth(mockUser: mockUser);
    // The mocks package registers itself as the platform implementation so
    // the default `FirebaseAuth.instance` will transparently use our mock.
    // We still need to call signIn so `currentUser` is non-null.
    await auth.signInWithCustomToken('dummy');
  });

  group('TimelineScreen state management', () {
    testWidgets('Day complete checkbox toggles & persists', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TimelineScreen()));
      await tester.pumpAndSettle();

      // Checkbox should start unchecked.
      expect(
        find.byWidgetPredicate(
          (w) => w is CheckboxListTile && w.value == false,
        ),
        findsOneWidget,
      );

      // Tap to mark complete.
      await tester.tap(find.text('Day fully logged'));
      await tester.pumpAndSettle();

      // Checkbox now checked.
      expect(
        find.byWidgetPredicate(
          (w) => w is CheckboxListTile && w.value == true,
        ),
        findsOneWidget,
      );

      // Firestore doc should exist.
      final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final snap = await firestore
          .collection('daily_logs')
          .doc('test_uid')
          .collection('logs')
          .doc(dateKey)
          .get();
      expect(snap.exists, true);
      expect(snap.get('complete'), true);
    });

    testWidgets('Habits expansion tile collapses and expands', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TimelineScreen()));
      await tester.pumpAndSettle();

      // HabitTracker visible when expanded.
      expect(find.byType(HabitTracker), findsWidgets);

      // Collapse.
      await tester.tap(find.text('Habits'));
      await tester.pumpAndSettle();
      expect(find.byType(HabitTracker), findsNothing);

      // Expand again.
      await tester.tap(find.text('Habits'));
      await tester.pumpAndSettle();
      expect(find.byType(HabitTracker), findsWidgets);
    });

    testWidgets('Scroll offset is cached per-date', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TimelineScreen()));
      await tester.pumpAndSettle();

      // Scroll the list down a bit.
      final listFinder = find.byType(ListView).first;
      await tester.drag(listFinder, const Offset(0, -600));
      await tester.pumpAndSettle();

      final listView = tester.widget<ListView>(listFinder);
      final firstOffset = listView.controller!.offset;
      expect(firstOffset, greaterThan(100));

      // Switch to next date (index 8 is today+1).
      final todayPlusOne = find.byType(GestureDetector).at(8);
      await tester.tap(todayPlusOne);
      await tester.pumpAndSettle();

      // Switch back to today (index 7).
      final todayTile = find.byType(GestureDetector).at(7);
      await tester.tap(todayTile);
      await tester.pumpAndSettle();

      final listView2 = tester.widget<ListView>(listFinder);
      final secondOffset = listView2.controller!.offset;

      // Offset restored (within small margin).
      expect((secondOffset - firstOffset).abs(), lessThan(20));
    });
  });
}