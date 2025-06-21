import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_logger/main.dart';
import 'package:habit_logger/screens/habits_screen.dart';
import 'package:habit_logger/screens/timeline_screen.dart';
import '../test/helpers.dart';

// A wrapper around FakeFirebaseFirestore that throws on any write to simulate
// network failures.
class ThrowingFirestore extends FakeFirebaseFirestore {
  ThrowingFirestore() : super();

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    return _ThrowingCollection(super.collection(path));
  }
}

class _ThrowingCollection extends CollectionReference<Map<String, dynamic>> {
  final CollectionReference<Map<String, dynamic>> _inner;
  _ThrowingCollection(this._inner);

  @override
  _ThrowingDoc doc([String? id]) => _ThrowingDoc(_inner.doc(id));

  // passthrough others
  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({bool? includeMetadataChanges}) => _inner.snapshots(includeMetadataChanges: includeMetadataChanges);
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) => _inner.get(options);
  @override
  FirebaseFirestore get firestore => _inner.firestore;
  @override
  String get id => _inner.id;
  @override
  Query<Map<String, dynamic>> limit(int n) => _inner.limit(n);
  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) => _inner.orderBy(field as String, descending: descending);
  // Other un-used methods just delegate
  noSuchMethod(Invocation i) => _inner.noSuchMethod(i);
}

class _ThrowingDoc extends DocumentReference<Map<String, dynamic>> {
  final DocumentReference<Map<String, dynamic>> _inner;
  _ThrowingDoc(this._inner);

  Future<T> _throw<T>() async => throw FirebaseException(plugin: 'Firestore', code: 'unavailable');

  // Writes throw
  @override
  Future<void> set(Map<String, dynamic>? data, [SetOptions? options]) => _throw();
  @override
  Future<void> update(Map<String, dynamic> data) => _throw();
  @override
  Future<void> delete() => _throw();

  // Reads delegate
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) => _inner.get(options);
  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({bool? includeMetadataChanges}) => _inner.snapshots(includeMetadataChanges: includeMetadataChanges);
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) => _ThrowingCollection(_inner.collection(path));
  @override
  FirebaseFirestore get firestore => _inner.firestore;
  @override
  String get id => _inner.id;
  @override
  DocumentReference<Map<String, dynamic>> get parent => _inner.parent;
  noSuchMethod(Invocation i) => _inner.noSuchMethod(i);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Firebase.initializeApp();
  });

  // Helper to pump app with a given firestore instance
  Future<void> _pumpWithStore(WidgetTester tester, FirebaseFirestore store) async {
    overrideFirestoreForTests(store);
    final user = MockUser(uid: 'uid', email: 'e@e.com');
    final auth = MockFirebaseAuth(mockUser: user);
    await auth.signInWithCustomToken('token');
    await tester.pumpWidget(const MaterialApp(home: TimelineScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('Habit creation failure shows snackbar', (tester) async {
    final throwing = ThrowingFirestore();
    await _pumpWithStore(tester, throwing);

    // open customize -> Habits menu
    await tester.tap(find.byTooltip('Customize'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Habits'));
    await tester.pumpAndSettle();

    // try to add empty habit -> validator message
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Please enter'), findsOneWidget);

    // enter valid name but write fails -> snackbar
    await tester.enterText(find.byType(TextFormField).first, 'Yoga');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Error adding habit'), findsOneWidget);
  });

  testWidgets('Settings save failure shows snackbar', (tester) async {
    final throwing = ThrowingFirestore();
    await _pumpWithStore(tester, throwing);

    // open customize -> Activities
    await tester.tap(find.byTooltip('Customize'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activities'));
    await tester.pumpAndSettle();

    // Add custom activity will attempt write and throw
    await tester.enterText(find.byType(TextField).first, 'Run');
    await tester.tap(find.byIcon(Icons.add).first);

    await tester.pumpAndSettle();
    expect(find.textContaining('Unable to save settings'), findsOneWidget);
  });

  testWidgets('Day complete checkbox rolls back on failure', (tester) async {
    final throwing = ThrowingFirestore();
    await _pumpWithStore(tester, throwing);

    final cbFinder = find.byType(CheckboxListTile);
    expect(tester.widget<CheckboxListTile>(cbFinder).value, false);

    await tester.tap(cbFinder);
    await tester.pumpAndSettle();

    // state should revert to false due to error
    expect(tester.widget<CheckboxListTile>(cbFinder).value, false);
    expect(find.textContaining('Could not update day status'), findsOneWidget);
  });
}